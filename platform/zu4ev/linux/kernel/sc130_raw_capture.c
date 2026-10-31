// SPDX-License-Identifier: GPL-2.0
/* One-shot RAW10-in-u16 capture using a dedicated VDMA and frame gate. */
#include <linux/completion.h>
#include <linux/delay.h>
#include <linux/dmaengine.h>
#include <linux/dma-mapping.h>
#include <linux/dma/xilinx_dma.h>
#include <linux/fs.h>
#include <linux/io.h>
#include <linux/iopoll.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/slab.h>
#include <linux/uaccess.h>
#include <raw_capture_contract.h>

#define RAW_WIDTH 1280U
#define RAW_HEIGHT 1024U
#define RAW_STRIDE (RAW_WIDTH * 2U)
#define RAW_SIZE (RAW_STRIDE * RAW_HEIGHT)
#define RAW_ID 0x52415731U
#define RAW_VERSION 0x00030000U
#define RAW_CONTROL 0x08U
#define RAW_STATUS 0x0cU
#define RAW_ARM_EPOCH 0x10U
#define RAW_RESULT_EPOCH 0x14U
#define RAW_FLAGS 0x18U
#define RAW_ACK 0x1cU
#define RAW_WORDS 0x28U
#define RAW_LINES 0x2cU
#define RAW_GUARD 0x74U
#define RAW_BYTES 0x78U
#define RAW_IRQ_ENABLE 0x3cU
#define RAW_ARM 1U
#define RAW_ABORT 2U

struct sc130_raw_device
{
    struct miscdevice misc;
    struct device *pDev;
    struct dma_chan *pChan;
    void __iomem *pGate;
    void *pBuffer;
    dma_addr_t dmaAddress;
    struct completion dmaDone;
    struct mutex lock;
    unsigned int epoch;
    bool opened;
    bool captured;
    bool quarantined;
};

static void sc130_raw_dma_complete(void *pArg)
{
    struct sc130_raw_device *pRaw = pArg;
    complete(&pRaw->dmaDone);
} /* end of sc130_raw_dma_complete */

static int sc130_raw_dma_halt(struct sc130_raw_device *pRaw)
{
    int state;
    int rc;
    u32 guard;
    u32 status;
    writel(0, pRaw->pGate + RAW_IRQ_ENABLE);
    writel(RAW_ABORT, pRaw->pGate + RAW_CONTROL);
    rc = dmaengine_terminate_sync(pRaw->pChan);
    if (0 == rc)
    {
        rc = read_poll_timeout(xilinx_vdma_channel_is_halted, state, 0 != state,
                               10, 100000, false, pRaw->pChan);
        if (0 == rc && 1 != state)
        {
            rc = -EIO;
        }
    }
    if (0 == rc)
    {
        rc = readl_poll_timeout(pRaw->pGate + RAW_GUARD, guard, (guard & BIT(2)),
                                10, 100000);
    }
    if (0 == rc)
    {
        rc = readl_poll_timeout(pRaw->pGate + RAW_STATUS, status,
                                0 == (status & (BIT(1) | BIT(2))), 10, 100000);
    }
    if (0 != rc)
    {
        /* Never release memory or unload callback code while DMA may be active. */
        if (!pRaw->quarantined)
        {
            pRaw->quarantined = true;
            __module_get(THIS_MODULE);
        }
        dev_crit(pRaw->pDev, "RAW DMA not quiescent; buffer quarantined until reboot\n");
        return -EIO;
    }
    writel(readl(pRaw->pGate + RAW_RESULT_EPOCH), pRaw->pGate + RAW_ACK);
    return 0;
} /* end of sc130_raw_dma_halt */

static int sc130_raw_frame_capture(struct sc130_raw_device *pRaw)
{
    struct xilinx_vdma_config config = {.frm_cnt_en = 1, .coalesc = 1, .park = 0};
    struct
    {
        struct dma_interleaved_template xt;
        struct data_chunk chunk;
    } transfer = {
        .xt = {.dir = DMA_DEV_TO_MEM, .dst_sgl = true, .dst_inc = true,
               .frame_size = 1, .numf = RAW_HEIGHT},
        .chunk = {.size = RAW_STRIDE},
    };
    struct dma_async_tx_descriptor *pDesc;
    dma_cookie_t cookie;
    u32 status;
    int state;
    int rc;

    if (pRaw->quarantined)
    {
        return -EIO;
    }
    rc = sc130_raw_dma_halt(pRaw);
    if (0 != rc)
    {
        return rc;
    }
    rc = xilinx_vdma_channel_set_config(pRaw->pChan, &config);
    if (0 != rc)
    {
        return rc;
    }
    reinit_completion(&pRaw->dmaDone);
    transfer.xt.dst_start = pRaw->dmaAddress;
    pDesc = dmaengine_prep_interleaved_dma(pRaw->pChan, &transfer.xt,
                                           DMA_PREP_INTERRUPT | DMA_CTRL_ACK);
    if (NULL == pDesc)
    {
        return -EIO;
    }
    pDesc->callback = sc130_raw_dma_complete;
    pDesc->callback_param = pRaw;
    cookie = dmaengine_submit(pDesc);
    if (dma_submit_error(cookie))
    {
        return -EIO;
    }
    ++pRaw->epoch;
    writel(pRaw->epoch, pRaw->pGate + RAW_ARM_EPOCH);
    dma_async_issue_pending(pRaw->pChan);
    writel(RAW_ARM, pRaw->pGate + RAW_CONTROL);
    if (!wait_for_completion_timeout(&pRaw->dmaDone, msecs_to_jiffies(500)))
    {
        sc130_raw_dma_halt(pRaw);
        return -ETIMEDOUT;
    }
    if (DMA_COMPLETE != dma_async_is_tx_complete(pRaw->pChan, cookie, NULL, NULL))
    {
        sc130_raw_dma_halt(pRaw);
        return -EIO;
    }
    rc = readl_poll_timeout(pRaw->pGate + RAW_STATUS, status, (status & BIT(3)),
                            10, 100000);
    if (0 == rc)
    {
        rc = read_poll_timeout(xilinx_vdma_channel_is_halted, state, 0 != state,
                               10, 100000, false, pRaw->pChan);
        if (0 == rc && 1 != state)
        {
            rc = -EIO;
        }
    }
    if (0 == rc && !sc130_raw_result_valid(1, readl(pRaw->pGate + RAW_FLAGS),
                                            readl(pRaw->pGate + RAW_RESULT_EPOCH), pRaw->epoch,
                                            readl(pRaw->pGate + RAW_WORDS),
                                            readl(pRaw->pGate + RAW_LINES),
                                            readl(pRaw->pGate + RAW_GUARD),
                                            readl(pRaw->pGate + RAW_BYTES)))
    {
        rc = -EIO;
    }
    if (0 == rc && 0 != xilinx_vdma_channel_has_error(pRaw->pChan))
    {
        rc = -EIO;
    }
    if (0 != rc)
    {
        sc130_raw_dma_halt(pRaw);
        return rc;
    }
    writel(pRaw->epoch, pRaw->pGate + RAW_ACK);
    pRaw->captured = true;
    return 0;
} /* end of sc130_raw_frame_capture */

static int sc130_raw_file_open(struct inode *pInode, struct file *pFile)
{
    struct miscdevice *pMisc = pFile->private_data;
    struct sc130_raw_device *pRaw = container_of(pMisc, struct sc130_raw_device, misc);
    int rc = 0;
    (void)pInode;
    mutex_lock(&pRaw->lock);
    if (pRaw->opened || pRaw->quarantined)
    {
        rc = pRaw->quarantined ? -EIO : -EBUSY;
    }
    else
    {
        pRaw->opened = true;
        pRaw->captured = false;
        pFile->private_data = pRaw;
    }
    mutex_unlock(&pRaw->lock);
    return rc;
} /* end of sc130_raw_file_open */

static ssize_t sc130_raw_file_read(struct file *pFile, char __user *pOut,
                                   size_t count, loff_t *pPosition)
{
    struct sc130_raw_device *pRaw = pFile->private_data;
    ssize_t result;
    int rc;
    mutex_lock(&pRaw->lock);
    if (!pRaw->captured)
    {
        rc = sc130_raw_frame_capture(pRaw);
        if (0 != rc)
        {
            mutex_unlock(&pRaw->lock);
            return rc;
        }
    }
    result = simple_read_from_buffer(pOut, count, pPosition, pRaw->pBuffer, RAW_SIZE);
    mutex_unlock(&pRaw->lock);
    return result;
} /* end of sc130_raw_file_read */

static int sc130_raw_file_release(struct inode *pInode, struct file *pFile)
{
    struct sc130_raw_device *pRaw = pFile->private_data;
    (void)pInode;
    mutex_lock(&pRaw->lock);
    pRaw->opened = false;
    mutex_unlock(&pRaw->lock);
    return 0;
} /* end of sc130_raw_file_release */

static const struct file_operations sc130_raw_file_ops = {
    .owner = THIS_MODULE,
    .open = sc130_raw_file_open,
    .read = sc130_raw_file_read,
    .release = sc130_raw_file_release,
};

static int sc130_raw_driver_probe(struct platform_device *pPdev)
{
    struct sc130_raw_device *pRaw;
    int rc;
    pRaw = devm_kzalloc(&pPdev->dev, sizeof(*pRaw), GFP_KERNEL);
    if (NULL == pRaw)
    {
        return -ENOMEM;
    }
    pRaw->pDev = &pPdev->dev;
    pRaw->pGate = devm_platform_ioremap_resource(pPdev, 0);
    if (IS_ERR(pRaw->pGate))
    {
        return PTR_ERR(pRaw->pGate);
    }
    if (RAW_ID != readl(pRaw->pGate) || RAW_VERSION != readl(pRaw->pGate + 4))
    {
        return -ENODEV;
    }
    pRaw->pChan = dma_request_chan(&pPdev->dev, "raw");
    if (IS_ERR(pRaw->pChan))
    {
        return PTR_ERR(pRaw->pChan);
    }
    pRaw->pBuffer = dma_alloc_coherent(pRaw->pChan->device->dev, RAW_SIZE,
                                       &pRaw->dmaAddress, GFP_KERNEL);
    if (NULL == pRaw->pBuffer || upper_32_bits(pRaw->dmaAddress)
        || upper_32_bits(pRaw->dmaAddress + RAW_SIZE - 1U))
    {
        rc = -ENOMEM;
        goto release_buffer;
    }
    init_completion(&pRaw->dmaDone);
    mutex_init(&pRaw->lock);
    pRaw->misc.minor = MISC_DYNAMIC_MINOR;
    pRaw->misc.name = "sc130_raw10";
    pRaw->misc.fops = &sc130_raw_file_ops;
    pRaw->misc.parent = &pPdev->dev;
    platform_set_drvdata(pPdev, pRaw);
    rc = misc_register(&pRaw->misc);
    if (0 == rc)
    {
        return 0;
    }
release_buffer:
    if (pRaw->pBuffer)
    {
        dma_free_coherent(pRaw->pChan->device->dev, RAW_SIZE, pRaw->pBuffer, pRaw->dmaAddress);
    }
    dma_release_channel(pRaw->pChan);
    return rc;
} /* end of sc130_raw_driver_probe */

static void sc130_raw_driver_remove(struct platform_device *pPdev)
{
    struct sc130_raw_device *pRaw = platform_get_drvdata(pPdev);
    misc_deregister(&pRaw->misc);
    mutex_lock(&pRaw->lock);
    if (pRaw->opened || pRaw->quarantined || 0 != sc130_raw_dma_halt(pRaw))
    {
        mutex_unlock(&pRaw->lock);
        dev_crit(&pPdev->dev, "RAW capture cannot be safely removed\n");
        return;
    }
    dma_free_coherent(pRaw->pChan->device->dev, RAW_SIZE, pRaw->pBuffer, pRaw->dmaAddress);
    dma_release_channel(pRaw->pChan);
    mutex_unlock(&pRaw->lock);
} /* end of sc130_raw_driver_remove */

static const struct of_device_id sc130_raw_of_match[] = {
    {.compatible = "sc130,raw10-frame-gate-v1"},
    {},
};
MODULE_DEVICE_TABLE(of, sc130_raw_of_match);
static struct platform_driver sc130_raw_driver = {
    .probe = sc130_raw_driver_probe,
    .remove = sc130_raw_driver_remove,
    .driver = {.name = "sc130_raw10", .of_match_table = sc130_raw_of_match,
               .suppress_bind_attrs = true},
};
module_platform_driver(sc130_raw_driver);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("SC130 dedicated RAW10 one-shot capture");

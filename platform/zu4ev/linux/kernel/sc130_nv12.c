// SPDX-License-Identifier: GPL-2.0
/* Persistent coherent buffers: never free a live DMA mapping on STOP timeout. */
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/poll.h>
#include <linux/uaccess.h>
#include <linux/dma-buf.h>
#include <linux/dma-mapping.h>
#include <linux/scatterlist.h>
#include <linux/iopoll.h>
#include <linux/interrupt.h>
#include <linux/of.h>
#include <linux/ktime.h>
#include <linux/compat.h>
#include <linux/fdtable.h>
#include <linux/kref.h>
#include "sc130_nv12_uapi.h"
#define WIDTH 1280u
#define HEIGHT 1024u
#define STRIDE 1280u
#define BYTES (STRIDE*HEIGHT*3/2)
#define SLOTS 4
#define CTRL 8
#define STATUS 12
#define SLOT 16
#define BASE 20
#define PITCH 24
#define RELEASE 28
#define COMMAND 32
#define FRAME_BASE 36
#define FRAME_PITCH 40
#define FRAME_TAG 44
#define IDLE BIT(2)
struct nv_memory { struct device *dev; void *cpu; dma_addr_t dma; };
struct nv_slot { struct dma_buf *buf; struct nv_memory *mem; unsigned state; struct sc130_nv12_frame frame; };
struct nv_device {
    struct kref ref;
    struct device *dev;
    void __iomem *regs;
    struct miscdevice misc;
    struct mutex lock;
    wait_queue_head_t wait;
    struct nv_slot slot[SLOTS];
    bool opened, streaming, poisoned, dead;
    unsigned ready, sequence;
    int irq;
};
static struct sg_table *nv_map(struct dma_buf_attachment *attach, enum dma_data_direction dir)
{
    struct nv_memory *m=attach->dmabuf->priv;
    struct sg_table *sg=kzalloc(sizeof(*sg),GFP_KERNEL);
    int ret;
    if(!sg) return ERR_PTR(-ENOMEM);
    ret=dma_get_sgtable(m->dev,sg,m->cpu,m->dma,BYTES);
    if(ret) goto fail;
    ret=dma_map_sgtable(attach->dev,sg,dir,0);
    if(ret) { sg_free_table(sg);goto fail; }
    return sg;
fail:
    kfree(sg);return ERR_PTR(ret);
}
static void nv_unmap(struct dma_buf_attachment *attach, struct sg_table *sg, enum dma_data_direction dir)
{
    dma_unmap_sgtable(attach->dev,sg,dir,0);sg_free_table(sg);kfree(sg);
}
static int nv_mmap(struct dma_buf *buf, struct vm_area_struct *vma)
{
    struct nv_memory *m=buf->priv;
    return dma_mmap_coherent(m->dev,vma,m->cpu,m->dma,BYTES);
}
static void nv_free(struct dma_buf *buf)
{
    struct nv_memory *m=buf->priv;
    dma_free_coherent(m->dev,BYTES,m->cpu,m->dma);put_device(m->dev);kfree(m);
}
static const struct dma_buf_ops nv_buf_ops={
    .map_dma_buf=nv_map,.unmap_dma_buf=nv_unmap,.mmap=nv_mmap,.release=nv_free,
};
static int nv_alloc(struct nv_device *s,unsigned i)
{
    DEFINE_DMA_BUF_EXPORT_INFO(info);
    struct nv_memory *m=kzalloc(sizeof(*m),GFP_KERNEL);
    struct dma_buf *buf;
    if(!m) return -ENOMEM;
    m->dev=get_device(s->dev);
    m->cpu=dma_alloc_coherent(m->dev,BYTES,&m->dma,GFP_KERNEL);
    if(!m->cpu) { put_device(m->dev);kfree(m);return -ENOMEM; }
    if(upper_32_bits(m->dma) || m->dma+BYTES>0x100000000ULL) {
        dma_free_coherent(m->dev,BYTES,m->cpu,m->dma);put_device(m->dev);kfree(m);return -ERANGE;
    }
    info.ops=&nv_buf_ops;info.size=BYTES;info.flags=O_RDWR;info.priv=m;info.exp_name="sc130-nv12";
    buf=dma_buf_export(&info);
    if(IS_ERR(buf)) { dma_free_coherent(m->dev,BYTES,m->cpu,m->dma);put_device(m->dev);kfree(m);return PTR_ERR(buf); }
    s->slot[i].buf=buf;s->slot[i].mem=m;
    return 0;
}
/* Called with mutex held; TAKE is after writer B retirement, RELEASE after VCU DQBUF. */
static int nv_collect(struct nv_device *s)
{
    unsigned n;
    for(n=0;n<SLOTS && (readl(s->regs+STATUS)&1);n++) {
        u32 i=readl(s->regs+FRAME_TAG);
        if(i>=SLOTS || !s->slot[i].mem || s->slot[i].state ||
           readl(s->regs+FRAME_BASE)!=lower_32_bits(s->slot[i].mem->dma) ||
           readl(s->regs+FRAME_PITCH)!=STRIDE) { s->poisoned=true;s->streaming=false;writel(0,s->regs+CTRL);return -EPROTO; }
        dma_rmb();
        s->slot[i].frame=(struct sc130_nv12_frame){.index=i,.sequence=s->sequence++,.timestamp_ns=ktime_get_ns()};
        writel(2,s->regs+COMMAND);
        readl(s->regs+STATUS); /* Flush posted TAKE before processing another offer. */
        s->slot[i].state=1;s->ready|=BIT(i);
    }
    wake_up_interruptible(&s->wait);
    return 0;
}
static int nv_stop(struct nv_device *s)
{
    u32 status;
    int ret;
    writel(8,s->regs+COMMAND);
    ret=readl_poll_timeout(s->regs+STATUS,status,status&IDLE,10,1000000);
    s->streaming=false;
    if(ret) { s->poisoned=true;wake_up_interruptible(&s->wait);return ret; }
    writel(0,s->regs+CTRL);
    return nv_collect(s);
}
static irqreturn_t nv_irq(int irq,void *arg)
{
    struct nv_device *s=arg;
    mutex_lock(&s->lock);
    if(!s->dead) nv_collect(s);
    mutex_unlock(&s->lock);
    return IRQ_HANDLED;
}
static void nv_device_free(struct kref *ref)
{
    struct nv_device *s=container_of(ref,struct nv_device,ref);
    mutex_destroy(&s->lock);kfree(s);
}
static int nv_open(struct inode *inode,struct file *file)
{
    struct nv_device *s=container_of(file->private_data,struct nv_device,misc);
    int ret=0;
    mutex_lock(&s->lock);
    if(s->dead||s->poisoned) ret=-EIO;
    else if(s->opened) ret=-EBUSY;
    else { s->opened=true;kref_get(&s->ref);file->private_data=s; }
    mutex_unlock(&s->lock);return ret;
}
static long nv_ioctl(struct file *file,unsigned cmd,unsigned long arg)
{
    struct nv_device *s=file->private_data;
    void __user *user=(void __user *)arg;
    struct sc130_nv12_buffer b;
    struct sc130_nv12_frame frame;
    u32 i,j;
    int ret=0,fd;
    mutex_lock(&s->lock);
    if(s->dead||s->poisoned) { ret=-EIO;goto out; }
    switch(cmd) {
    case SC130_NV12_GETBUF:
        if(copy_from_user(&b,user,sizeof(b))) { ret=-EFAULT;break; }
        if(b.index>=SLOTS) { ret=-EINVAL;break; }
        get_dma_buf(s->slot[b.index].buf);
        fd=dma_buf_fd(s->slot[b.index].buf,O_CLOEXEC|O_RDWR);
        if(fd<0) { dma_buf_put(s->slot[b.index].buf);ret=fd;break; }
        b.fd=fd;b.size=BYTES;b.stride=STRIDE;b.width=WIDTH;b.height=HEIGHT;
        if(copy_to_user(user,&b,sizeof(b))) { close_fd(fd);ret=-EFAULT; }
        break;
    case SC130_NV12_START:
        if(s->streaming) break;
        if(!(readl(s->regs+STATUS)&IDLE)) { ret=-EBUSY;break; }
        writel(3,s->regs+CTRL);s->streaming=true;break;
    case SC130_NV12_STOP: ret=nv_stop(s);break;
    case SC130_NV12_DQBUF:
        if(!s->ready) { ret=-EAGAIN;break; }
        i=__ffs(s->ready);
        for(j=0;j<SLOTS;j++) if((s->ready&BIT(j)) &&
            (s32)(s->slot[j].frame.sequence-s->slot[i].frame.sequence)<0) i=j;
        frame=s->slot[i].frame;
        if(copy_to_user(user,&frame,sizeof(frame))) { ret=-EFAULT;break; }
        s->ready&=~BIT(i);s->slot[i].state=2;break;
    case SC130_NV12_QBUF:
        if(copy_from_user(&i,user,sizeof(i))) { ret=-EFAULT;break; }
        if(i>=SLOTS || s->slot[i].state!=2) { ret=-EINVAL;break; }
        writel(i,s->regs+RELEASE);writel(4,s->regs+COMMAND);
        readl(s->regs+STATUS);s->slot[i].state=0;break;
    default: ret=-ENOTTY;break;
    }
out:
    mutex_unlock(&s->lock);return ret;
}
static __poll_t nv_poll(struct file *file,poll_table *wait)
{
    struct nv_device *s=file->private_data;
    poll_wait(file,&s->wait,wait);
    if(READ_ONCE(s->dead)||READ_ONCE(s->poisoned)) return EPOLLERR;
    return READ_ONCE(s->ready) ? EPOLLIN|EPOLLRDNORM : 0;
}
static int nv_close(struct inode *inode,struct file *file)
{
    struct nv_device *s=file->private_data;
    unsigned i;
    mutex_lock(&s->lock);
    if(!s->dead && !nv_stop(s)) {
        /* Userspace must cancel VCU first, as with returning any DMA-BUF. */
        for(i=0;i<SLOTS;i++) if(s->slot[i].state) {
            writel(i,s->regs+RELEASE);writel(4,s->regs+COMMAND);readl(s->regs+STATUS);
            s->slot[i].state=0;
        }
        s->ready=0;
    }
    s->opened=false;
    mutex_unlock(&s->lock);kref_put(&s->ref,nv_device_free);return 0;
}
static const struct file_operations nv_fops={
    .owner=THIS_MODULE,.open=nv_open,.release=nv_close,.unlocked_ioctl=nv_ioctl,
    .compat_ioctl=compat_ptr_ioctl,.poll=nv_poll,.llseek=noop_llseek,
};
static int nv_probe(struct platform_device *pdev)
{
    struct nv_device *s;
    unsigned i;
    int ret,irq;
    s=kzalloc(sizeof(*s),GFP_KERNEL);if(!s) return -ENOMEM;
    kref_init(&s->ref);
    s->dev=&pdev->dev;mutex_init(&s->lock);init_waitqueue_head(&s->wait);
    ret=dma_set_mask_and_coherent(s->dev,DMA_BIT_MASK(32));if(ret) goto free_device;
    s->regs=devm_platform_ioremap_resource(pdev,0);if(IS_ERR(s->regs)) { ret=PTR_ERR(s->regs);goto free_device; }
    if(readl(s->regs)!=0x4e563132 || readl(s->regs+4)!=2) { ret=-ENODEV;goto free_device; }
    if(!(readl(s->regs+STATUS)&IDLE)) { ret=-EBUSY;goto free_device; }
    irq=platform_get_irq(pdev,0);if(irq<0) { ret=irq;goto free_device; }
    writel(0,s->regs+CTRL);readl(s->regs+STATUS);
    for(i=0;i<SLOTS;i++) {
        ret=nv_alloc(s,i);if(ret) goto free_buffers;
    }
    for(i=0;i<SLOTS;i++) {
        writel(i,s->regs+SLOT);writel(lower_32_bits(s->slot[i].mem->dma),s->regs+BASE);
        writel(STRIDE,s->regs+PITCH);
        if(!(readl(s->regs+STATUS)&2)) { ret=-EBUSY;goto free_buffers; }
        writel(1,s->regs+COMMAND);readl(s->regs+STATUS);
    }
    ret=devm_request_threaded_irq(s->dev,irq,NULL,nv_irq,IRQF_ONESHOT,dev_name(s->dev),s);
    if(ret) goto free_buffers;
    s->irq=irq;
    s->misc=(struct miscdevice){.minor=MISC_DYNAMIC_MINOR,.name="sc130-nv12",.fops=&nv_fops,.parent=s->dev};
    ret=misc_register(&s->misc);if(ret) { devm_free_irq(s->dev,s->irq,s);goto free_buffers; }
    platform_set_drvdata(pdev,s);return 0;
free_buffers:
    for(i=0;i<SLOTS;i++) if(s->slot[i].buf) dma_buf_put(s->slot[i].buf);
free_device:
    kref_put(&s->ref,nv_device_free);return ret;
}
static void nv_remove(struct platform_device *pdev)
{
    struct nv_device *s=platform_get_drvdata(pdev);
    unsigned i;
    misc_deregister(&s->misc);
    mutex_lock(&s->lock);
    if(nv_stop(s)) dev_err(s->dev,"STOP timeout: DMA buffers intentionally pinned until reset\n");
    else for(i=0;i<SLOTS;i++) dma_buf_put(s->slot[i].buf);
    s->dead=true;wake_up_interruptible(&s->wait);
    mutex_unlock(&s->lock);
    devm_free_irq(s->dev,s->irq,s);
    kref_put(&s->ref,nv_device_free);
}
static const struct of_device_id nv_match[]={ {.compatible="sc130,nv12-capture-v2"},{} };
MODULE_DEVICE_TABLE(of,nv_match);
static struct platform_driver nv_driver={.probe=nv_probe,.remove=nv_remove,.driver={.name="sc130-nv12",.of_match_table=nv_match}};
module_platform_driver(nv_driver);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("SC130 final-ISP NV12 DMA-BUF capture");
MODULE_IMPORT_NS(DMA_BUF);

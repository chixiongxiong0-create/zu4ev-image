# Source provenance and license notices

This platform snapshot does not relicense the imported camera platform or
declare every file Apache-2.0. Original copyright notices and SPDX identifiers
are preserved byte-for-byte; applicable file-level notices control each file.
The parent repository retains the upstream Ibex license and notices.

| Source group | Notice retained |
|---|---|
| AMD/Xilinx FSBL application and XIicPs driver source | Original Xilinx/AMD copyright headers and `SPDX-License-Identifier: MIT`; original installed SDK license text is included as [`LICENSES/AMD-Xilinx-MIT.txt`](LICENSES/AMD-Xilinx-MIT.txt) |
| Custom Linux capture modules and kernel modifications | Existing GPL-2.0 SPDX/file notices; matching Linux license text is included as [`LICENSES/GPL-2.0.txt`](LICENSES/GPL-2.0.txt) |
| Camera/ISP/platform application source | Original source headers and notices are preserved; files lacking a header are not automatically assigned the parent repository's license by this publication |
| Ibex integration copies | Original integration headers are preserved; authoritative maintained sources remain under `integration/small/` |

Only the small FSBL application/driver source subset needed to review this
build is included. Proprietary tool binaries, generated IP netlists, complete
SDK/BSP libraries and the full Linux source distribution are not copied.
Source paths and hashes are recorded in `source_manifest.json`; no credentials,
editor settings, UART dumps, crash dumps or local machine logs are part of
this source export.

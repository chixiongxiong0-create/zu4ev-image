# Source through Vivado Hardware Manager after loading board_validation firmware.
# Reading is the default. Video readiness must be asserted separately after
# confirming that the source video clock is running and remains running.
namespace eval ibex_validation {
  proc log {message} {
    # HTTP Tcl interpreters can lack stdout even when Hardware Manager works.
    if {[lsearch -exact [chan names] stdout] >= 0} {
      puts $message
    } else {
      send_msg_id {IBEX 1-1} INFO $message
    }
  }
  variable master
  variable serial 0
  set masters [get_hw_axis -quiet]
  if {[llength $masters] != 1} {error "Expected one Ibex JTAG AXI master"}
  set master [lindex $masters 0]

  proc word {offset} {
    variable master
    variable serial
    set name ibex_validation_[incr serial]
    create_hw_axi_txn $name $master -type READ -address [format %08x [expr {0x0023f000+$offset}]] -len 1
    set txn [get_hw_axi_txns $name]
    run_hw_axi $txn
    set value [get_property DATA $txn]
    delete_hw_axi_txn $txn
    if {![regexp {^[0-9a-fA-F]{8}$} $value]} {error "Invalid mailbox data: $value"}
    scan $value %x decoded
    return $decoded
  }

  proc video_ready {{enable 1}} {
    variable master
    variable serial
    if {$enable ni {0 1}} {error "Video readiness must be 0 or 1"}
    set name ibex_validation_[incr serial]
    if {$enable} {set data 56494431} else {set data 00000000}
    create_hw_axi_txn $name $master -type WRITE -address 0023f02c -data $data -len 1
    set txn [get_hw_axi_txns $name]
    run_hw_axi $txn
    delete_hw_axi_txn $txn
  }

  # This status collection is not atomic; repeat changing fields when needed.
  proc status {} {
    set result [dict create]
    foreach {name offset} {
      magic 0 version 4 size 8 state 12 heartbeat 16 errors 20 signature 24
      publish_seq 28 command 32 request 36 ack 40 video_ready 44 owner 48
      isp_id 52 isp_version 56 capabilities 60 before 64 trial 68 observed 72
      restored 76 dirty 80 mcause 84 mepc 88 mtval 92 snapshot_retries 164 tests 168
    } {
      set value [word $offset]
      dict set result $name $value
      log [format "IBEX_VALIDATION %-12s %08x" $name $value]
    }
    return $result
  }

  proc check_boot {} {
    foreach {offset expected label} {0 0x49564231 magic 4 0x00010000 version 8 0xac size} {
      if {[word $offset] != $expected} {error "Board-validation firmware $label mismatch"}
    }
    set before [word 16]
    after 100
    set current [word 16]
    if {$before == $current} {error "CPU heartbeat did not advance"}
    if {[word 20] != 0 || [word 12] == 8} {error "Firmware reports an error/trap; inspect status"}
    log [format "IBEX_VALIDATION_BOOT_PASS heartbeat=%08x->%08x" $before $current]
  }

  # Request polling stop, then prove the firmware returned to its RAM-only
  # heartbeat loop. Keep the actual video clock running while traffic drains.
  # No other host may change ready/request or reset the CPU during this check.
  proc pause {} {
    video_ready 0
    if {[word 44] != 0} {error "Video-readiness clear did not read back"}
    for {set attempt 0} {$attempt < 20} {incr attempt} {
      set first [word 28]
      set before [word 16]
      after 100
      set current [word 16]
      set last [word 28]
      if {[word 44] != 0} {error "Another host changed video readiness"}
      if {$first == $last && ($last & 1) == 0 && $before != $current} {
        if {[word 80] != 0 || [word 20] != 0 || [word 12] == 8 || [word 36] != [word 40]} {
          error "Polling stopped, but dirty/error/trap/pending request prevents a safe handoff"
        }
        log [format "IBEX_VALIDATION_PAUSED publish_seq=%08x heartbeat=%08x->%08x" $last $before $current]
        return $last
      }
    }
    error "Firmware polling did not quiesce; keep ownership and video clock unchanged"
  }

  # Values below are individually sampled, not a frozen multiword snapshot.
  # Only accept a consistent firmware publication if publish_seq is unchanged
  # and even. FE/SOF/pending originate from separate source snapshots; even a
  # consistent publication does not make them simultaneous with image stats.
  proc sample {} {
    set first [word 28]
    set result [dict create publish_seq_before $first]
    foreach {name offset} {
      result_seq 96 frame 100 mean 104 count 108 sum_lo 112 sum_hi 116
      stats_flags 120 region_black 124 bad_frames 128 overruns 132
      roi_x 136 roi_y 140 roi_width 144 roi_height 148 fe_seq 152 sof_seq 156 pending 160
    } {
      dict set result $name [word $offset]
    }
    set last [word 28]
    dict set result publish_seq_after $last
    dict set result coherent [expr {$first == $last && ($last & 1) == 0}]
    log "IBEX_VALIDATION_SAMPLE $result"
    return $result
  }
}
ibex_validation::log {Ibex mailbox helpers ready: ibex_validation::check_boot/status/sample}
ibex_validation::log {Assert ibex_validation::video_ready only after verifying the video clock.}
ibex_validation::log {Require ibex_validation::pause success before CPU reset or reclaiming ISP ownership.}


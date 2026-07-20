`ifndef YIFPGA_DEBUG_PKG_VH
`define YIFPGA_DEBUG_PKG_VH

`define YFD_SOF                 8'hA5
`define YFD_VERSION             8'h01
`define YFD_MAX_PAYLOAD_BYTES   8'd32

`define YFD_TYPE_HEARTBEAT      8'h01
`define YFD_TYPE_DEBUG_PRINT    8'h02
`define YFD_TYPE_EVENT          8'h03
`define YFD_TYPE_WATCH          8'h04
`define YFD_TYPE_STATUS         8'h05

`define YFD_LEVEL_DEBUG         8'd0
`define YFD_LEVEL_INFO          8'd1
`define YFD_LEVEL_WARNING       8'd2
`define YFD_LEVEL_ERROR         8'd3

`endif

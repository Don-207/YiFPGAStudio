`ifndef YIFPGA_TRACE_PKG_VH
`define YIFPGA_TRACE_PKG_VH

`define YFD_TYPE_TRACE_SPAN_BEGIN 8'h10
`define YFD_TYPE_TRACE_SPAN_END   8'h11
`define YFD_TYPE_TRACE_MARK       8'h12
`define YFD_TYPE_TRACE_VALUE      8'h13
`define YFD_TYPE_TRACE_DROP       8'h14

`define YFD_TRACE_LEN_SPAN_BEGIN  8'd12
`define YFD_TRACE_LEN_SPAN_END    8'd13
`define YFD_TRACE_LEN_MARK        8'd11
`define YFD_TRACE_LEN_VALUE       8'd12
`define YFD_TRACE_LEN_DROP        8'd10

`define YFD_TRACE_STATUS_OK       8'd0
`define YFD_TRACE_STATUS_WARN     8'd1
`define YFD_TRACE_STATUS_ERROR    8'd2
`define YFD_TRACE_STATUS_TIMEOUT  8'd3

`define YFD_TRACE_ID_GLOBAL       16'h0000
`define YFD_TRACE_ID_DMA          16'h0001
`define YFD_TRACE_ID_FRAME        16'h0002
`define YFD_TRACE_ID_FIFO         16'h0003
`define YFD_TRACE_ID_IRQ          16'h0004

`endif

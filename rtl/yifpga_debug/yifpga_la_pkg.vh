`ifndef YIFPGA_LA_PKG_VH
`define YIFPGA_LA_PKG_VH

`define YFD_TYPE_LA_CAPTURE_HEADER      8'h40
`define YFD_TYPE_LA_SAMPLE_DATA         8'h41
`define YFD_TYPE_LA_CAPTURE_STATUS      8'h42
`define YFD_TYPE_LA_TRIGGER_EVENT       8'h43
`define YFD_TYPE_LA_CHANNEL_MANIFEST    8'h44
`define YFD_TYPE_LA_CFG_REQ             8'h45
`define YFD_TYPE_LA_CFG_RESP            8'h46

`define YFD_LA_LEN_CAPTURE_HEADER       8'd24
`define YFD_LA_LEN_SAMPLE_DATA          8'd32
`define YFD_LA_LEN_CAPTURE_STATUS       8'd20
`define YFD_LA_LEN_TRIGGER_EVENT        8'd20

`define YFD_LA_STATE_IDLE               3'd0
`define YFD_LA_STATE_ARMED              3'd1
`define YFD_LA_STATE_CAPTURING          3'd2
`define YFD_LA_STATE_DONE               3'd3
`define YFD_LA_STATE_READOUT            3'd4
`define YFD_LA_STATE_ERROR              3'd5

`define YFD_LA_FLAG_VALID               16'h0001
`define YFD_LA_FLAG_TRIGGERED           16'h0002
`define YFD_LA_FLAG_FORCED              16'h0004
`define YFD_LA_FLAG_OVERFLOW            16'h0008
`define YFD_LA_FLAG_PARTIAL             16'h0010

`define YFD_LA_ERROR_NONE               8'd0
`define YFD_LA_ERROR_CONFIG             8'd1
`define YFD_LA_ERROR_BUSY               8'd2
`define YFD_LA_ERROR_READOUT            8'd3

`define YFD_LA_TRIGGER_DISABLED         4'd0
`define YFD_LA_TRIGGER_LEVEL            4'd1
`define YFD_LA_TRIGGER_EDGE_RISING      4'd2
`define YFD_LA_TRIGGER_EDGE_FALLING     4'd3
`define YFD_LA_TRIGGER_MASK_MATCH       4'd4

`define YFD_LA_SAMPLE_WIDTH_BITS        16'd32
`define YFD_LA_SAMPLE_BYTES             8'd4
`define YFD_LA_CHANNEL_COUNT            16'd32
`define YFD_LA_MAX_SAMPLE_DEPTH         16'd128
`define YFD_LA_SAMPLE_DATA_BYTES        8'd20
`define YFD_LA_SAMPLES_PER_CHUNK        8'd5
`define YFD_LA_VERSION_VALUE            32'h00010000
`define YFD_LA_ID_VALUE                 32'h4F464C41

`define YFD_MON_ADDR_LA_ID              16'h0060
`define YFD_MON_ADDR_LA_VERSION         16'h0064
`define YFD_MON_ADDR_LA_CONTROL         16'h0068
`define YFD_MON_ADDR_LA_STATUS          16'h006C
`define YFD_MON_ADDR_LA_SAMPLE_DIVISOR  16'h0070
`define YFD_MON_ADDR_LA_CAPTURE_DEPTH   16'h0074
`define YFD_MON_ADDR_LA_PRETRIGGER_DEPTH 16'h0078
`define YFD_MON_ADDR_LA_TRIGGER_MODE    16'h007C
`define YFD_MON_ADDR_LA_TRIGGER_CHANNEL 16'h0080
`define YFD_MON_ADDR_LA_TRIGGER_VALUE   16'h0084
`define YFD_MON_ADDR_LA_TRIGGER_MASK    16'h0088
`define YFD_MON_ADDR_LA_COMMAND         16'h008C
`define YFD_MON_ADDR_LA_CAPTURE_ID      16'h0090
`define YFD_MON_ADDR_LA_CHANNEL_MASK    16'h0094

`endif

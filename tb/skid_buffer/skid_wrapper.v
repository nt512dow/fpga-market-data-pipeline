module skid_wrapper #(parameter OPT_LOWPOWER = 0, OPT_OUTREG = 0, DATA_WIDTH = 9) (
    //module to match the format of cocotbext.axi
    input clk, rst,
    input [DATA_WIDTH-2:0] s_axis_tdata, //DATA_WIDTH includes tlast
    input s_axis_tlast,
    input s_axis_tvalid,
    output s_axis_tready,

    output [DATA_WIDTH-2:0] m_axis_tdata,
    output m_axis_tlast,
    output m_axis_tvalid,
    input m_axis_tready
);
    wire [DATA_WIDTH-1:0] o_data;

    skid_buffer #(.OPT_LOWPOWER(OPT_LOWPOWER), .OPT_OUTREG(OPT_OUTREG), .DATA_WIDTH(DATA_WIDTH)) skid_buffer_unit (
        .i_valid(s_axis_tvalid),
        .i_data({s_axis_tlast, s_axis_tdata}), //to keep the data in the LSBs
        .o_ready(s_axis_tready),

        .o_valid(m_axis_tvalid), 
        .o_data(o_data),
        .i_ready(m_axis_tready),

        .i_reset(rst), 
        .clk(clk)
    );

    assign {m_axis_tlast, m_axis_tdata} = o_data;
endmodule

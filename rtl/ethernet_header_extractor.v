module ethernet_header_extractor #(parameter BEAT_SIZE = 64) (
    input clk,
    input reset,

    input [BEAT_SIZE-1:0] s_axis_tdata,
    input [7:0] s_axis_tkeep,
    input s_axis_tlast,
    input s_axis_tvalid,
    output s_axis_tready,

    output [BEAT_SIZE-1:0] m_axis_tdata,
    output [7:0] m_axis_tkeep,
    output m_axis_tlast,
    output m_axis_tvalid,
    input m_axis_tready,

    output reg [47:0] destination_MAC,
    output reg [47:0] source_MAC,
    output reg [15:0] ether_type,
    output reg valid_header
);
    //pass through 
    assign m_axis_tdata  = s_axis_tdata;
    assign m_axis_tkeep  = s_axis_tkeep;
    assign m_axis_tlast  = s_axis_tlast;
    assign m_axis_tvalid = s_axis_tvalid;
    assign s_axis_tready = m_axis_tready;

    wire transfer_happening;
    assign transfer_happening = s_axis_tready && s_axis_tvalid;

    reg [1:0] beat_count;

    initial beat_count = 0;
    always @(posedge clk) begin
        if (reset) begin
            beat_count <= 0;
        end else if (transfer_happening) begin 
            if (s_axis_tlast) begin
                beat_count <= 0;
            end else if (beat_count == 0) begin 
                beat_count <= 1;
            end else if (beat_count == 1) begin 
                beat_count <= 2;
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin 
            destination_MAC <= 0;
            source_MAC <= 0;
            ether_type <= 0;
        end else if (transfer_happening) begin
            if (beat_count == 0) begin
            //unpacking data, assuming big endian
                destination_MAC <= {s_axis_tdata[7:0],
                                    s_axis_tdata[15:8],
                                    s_axis_tdata[23:16],
                                    s_axis_tdata[31:24], 
                                    s_axis_tdata[39:32], 
                                    s_axis_tdata[47:40]};
                source_MAC [47:32] <= {s_axis_tdata[55:48], s_axis_tdata[63:56]};
            end else if (beat_count == 1) begin
                source_MAC [31:0] <= {s_axis_tdata[7:0],
                                    s_axis_tdata[15:8],
                                    s_axis_tdata[23:16],
                                    s_axis_tdata[31:24]};
                ether_type <= {s_axis_tdata[39:32], s_axis_tdata[47:40]};
            end 
        end
    end

    initial valid_header = 0;
    always @ (posedge clk) begin
        if (reset) begin
            valid_header <= 0;
        end else if (transfer_happening) begin
            if (beat_count == 1) begin
                valid_header <= 1;
            end else if (beat_count == 0 && !s_axis_tlast) begin
                //this keeps the valid_header flag high for as long as possible
                //avoiding a situation where the flag drops just because the beat ends
                valid_header <= 0;
            end
        end
    end
  
endmodule

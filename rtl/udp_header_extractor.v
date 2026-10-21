module udp_header_extractor #(parameter BEAT_SIZE = 64, PORT = 16'h5678) (
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

    input ok_ip,
    input valid_ip,
    input [15:0] ip_udp_payload_length,

    output reg [15:0] source_port,
    output reg [15:0] destination_port,
    output reg [15:0] udp_length,
    output reg [15:0] checksum,
    output reg valid_udp,
    output reg ok_udp
);
// contract: extracts the source port, destination port, udp_length of (udp header + payload)
// valid_udp : rises with ok_udp, stays high until next frame's beat 0
//            asserts whether the relevant fields have bits we want to keep
// ok_udp    : meaningful only while ip_valid=1. 1 iff ok_ip, destination port is correct, udp_length field is correct
//             correct.
// Stalls   : counters advance only on tvalid && tready
// Bad frame: stream still passes; ok_udp=0; downstream must discard.
// checksum is passthrough unchecked.

    //pass through 
    assign m_axis_tdata  = s_axis_tdata;
    assign m_axis_tkeep  = s_axis_tkeep;
    assign m_axis_tlast  = s_axis_tlast;
    assign m_axis_tvalid = s_axis_tvalid;
    assign s_axis_tready = m_axis_tready;

    wire transfer_happening;
    assign transfer_happening = s_axis_tready && s_axis_tvalid;

    reg [2:0] beat_count;

    initial beat_count = 0;
    always @(posedge clk) begin
        if (reset) begin
            beat_count <= 0;
        end else if (transfer_happening) begin 
            if (s_axis_tlast) begin
                beat_count <= 0;
            end else if (beat_count <= 5) begin
                beat_count <= beat_count + 1;
            end
        end 
    end

    initial begin
        source_port = 0;
        destination_port = 0;
     udp_length = 0;
    end
    always @(posedge clk) begin
        if (reset) begin
            source_port <= 0;
            destination_port <= 0;
            udp_length <= 0;
        end else if (transfer_happening) begin
            if (beat_count == 4) begin
                source_port <= {s_axis_tdata[23:16], s_axis_tdata[31:24]};
                destination_port <= {s_axis_tdata[39:32], s_axis_tdata[47:40]};
                udp_length <= {s_axis_tdata[55:48], s_axis_tdata[63:56]};
            end
        end
    end

    initial checksum = 0;
    always @(posedge clk) begin
        if (reset) begin
            checksum <= 0;
        end else if (transfer_happening) begin
            if (beat_count == 5) begin
                checksum <= {s_axis_tdata[7:0], s_axis_tdata[15:8]};
            end
        end
    end

    initial begin
        valid_udp = 0;
        ok_udp = 0;
    end
    always @(posedge clk) begin
        if (reset) begin 
            valid_udp <= 0;
            ok_udp <= 0;
        end else if (transfer_happening && beat_count == 0) begin 
            valid_udp <= 0;
            ok_udp <= 0;
        end else if (beat_count == 6 && !valid_udp && valid_ip) begin
            //beat_count == 6 ensures that all lanes are valid, so we don't have to do a tkeep check for valid_udp
            valid_udp <= 1;
            ok_udp <= (ok_ip 
                      && destination_port == PORT 
                      && udp_length == ip_udp_payload_length - 20);
        end 
    end


endmodule

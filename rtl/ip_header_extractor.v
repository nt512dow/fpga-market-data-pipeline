module ip_header_extractor #(parameter BEAT_SIZE = 64) (
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

    input valid_ethernet_header,
    input [15:0] ether_type,

    output reg [3:0] ip_version,
    output reg [3:0] ip_header_length,
    output reg [7:0] differentiated_service_field,

    output reg [15:0] ip_udp_payload_length,
    output reg [15:0] identification,
    output reg [15:0] fragmentation,
    output reg [7:0] time_to_live,
    output reg [7:0] protocol,

    output reg [15:0] header_checksum,
    output reg [31:0] source_ip_address,
    output reg [31:0] destination_ip_address,

    output reg valid_ip,
    output reg ok_ip
);
// contract
// Captured fields (valid while ip_valid=1): protocol, src_ip, dst_ip, ip_udp_payload_length
// valid_ip : rises with ok_ip (the cycle after beat 4 is transferred), stays high until next frame's beat 0
//            asserts whether the relevant fields have bits we want to keep
// ok_ip    : meaningful only while ip_valid=1. 1 iff ethertype==0x0800, version==4, IHL==5,
//            not fragmented, protocol==17, checksum correct.
//            asserts if all those fields are correct
// Stalls   : counters advance only on tvalid && tready
// Bad frame: stream still passes; ok_ip=0; downstream must discard.

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
            end else if (beat_count <= 4) begin
                beat_count <= beat_count + 1;
            end
        end 
    end

    reg ok_ethernet;

    initial ok_ethernet = 0;
    always @(posedge clk) begin
        if (reset) begin
            ok_ethernet <= 0;
        end else if (transfer_happening) begin
            if (beat_count == 0) begin
                ok_ethernet <= 0;
            end else if (beat_count == 2 && valid_ethernet_header && ether_type == 16'h0800) begin
                //ethernet header information is ready after beat 1 so we can sample it on beat 2
                ok_ethernet <= 1;
            end
        end
    end

    //beat 0 is a passthrough of ethernet header information

    //beat 1
    initial begin 
        ip_version = 0;
        ip_header_length = 0;
        differentiated_service_field = 0;
    end
    always @(posedge clk) begin
        if (reset) begin
            ip_version <= 0;
            ip_header_length <= 0;
            differentiated_service_field <= 0;
        end else if (transfer_happening) begin
            if (beat_count == 1) begin 
                ip_version <= s_axis_tdata[55:52];
                ip_header_length <= s_axis_tdata[51:48];
                differentiated_service_field <= s_axis_tdata[63:56];
            end
        end
    end
    
    //beat 2
    initial begin 
        ip_udp_payload_length = 0;
        identification = 0;
        fragmentation = 0;
        time_to_live = 0;
        protocol = 0;
    end
    always @(posedge clk) begin
        if (reset) begin 
            ip_udp_payload_length <= 0;
            identification <= 0;
            fragmentation <= 0;
            time_to_live <= 0;
            protocol <= 0;
        end else if (transfer_happening) begin
            if (beat_count == 2) begin 
                ip_udp_payload_length <= {s_axis_tdata[7:0], s_axis_tdata[15:8]};
                identification <= {s_axis_tdata[23:16], s_axis_tdata[31:24]};
                fragmentation <= {s_axis_tdata[39:32], s_axis_tdata[47:40]};
                time_to_live <= {s_axis_tdata[55:48]};
                protocol <= {s_axis_tdata[63:56]};
            end
        end
    end

    //beat 3
    initial begin
        header_checksum = 0;
        source_ip_address = 0;
        destination_ip_address [31:16] = 0;
    end
    always @(posedge clk) begin
        if (reset) begin
            header_checksum <= 0;
            source_ip_address <= 0;
            destination_ip_address [31:16] <= 0;
        end else if (transfer_happening) begin
            if (beat_count == 3) begin
                header_checksum <= {s_axis_tdata[7:0], s_axis_tdata[15:8]};
                source_ip_address <= {s_axis_tdata[23:16], s_axis_tdata[31:24], s_axis_tdata[39:32], s_axis_tdata[47:40]};
                destination_ip_address [31:16] <= {s_axis_tdata[55:48], s_axis_tdata[63:56]};
            end
        end
    end

    //beat 4
    initial destination_ip_address [15:0] = 0;
    always @(posedge clk) begin
        if (reset) begin
            destination_ip_address [15:0] <= 0;
        end else if (transfer_happening) begin
            if (beat_count == 4) begin
                destination_ip_address [15:0] <= {s_axis_tdata[7:0], s_axis_tdata[15:8]};
            end
        end
    end

    wire [15:0] w0;
    wire [15:0] w1;
    wire [15:0] w2;
    wire [15:0] w3;

    assign w0 = {s_axis_tdata[7:0],   s_axis_tdata[15:8]};
    assign w1 = {s_axis_tdata[23:16], s_axis_tdata[31:24]};
    assign w2 = {s_axis_tdata[39:32], s_axis_tdata[47:40]};
    assign w3 = {s_axis_tdata[55:48], s_axis_tdata[63:56]};

    wire [16:0] pair_one;
    wire [16:0] pair_two;
    wire [17:0] beat_sum;

    assign pair_one = w0 + w1;
    assign pair_two = w2 + w3;
    assign beat_sum = pair_one + pair_two;
 
    reg [20:0] checksum;
    
    initial checksum = 0;
    always @(posedge clk) begin 
        if (reset) begin 
            checksum <= 0;
        end else if (transfer_happening) begin
            if (beat_count == 0) begin
                checksum <= 0;
            end else if (beat_count == 1) begin 
                checksum <= checksum + w3;
            end else if (beat_count == 2 || beat_count == 3) begin
                checksum <= checksum + beat_sum;
            end else if (beat_count == 4) begin
                checksum <= checksum + w0;
            end
        end
    end

    wire [16:0] fold_one;
    wire ok_checksum;
    
    assign fold_one = checksum[15:0] + checksum[20:16];
    //assign fold_two = fold_one[15:0] + fold_one[16];
    assign ok_checksum = (fold_one == 17'h0FFFF || fold_one == 17'h1FFFE);


    always @(posedge clk) begin
        if (reset) begin
            valid_ip <= 0;
            ok_ip    <= 0;
        end else if (transfer_happening && beat_count == 0) begin
            valid_ip <= 0;
            ok_ip    <= 0;
        end else if (beat_count == 5 && !valid_ip) begin 
            //happens once checksum is complete, triggers once per transmission
            valid_ip <= 1;
            ok_ip    <= ok_ethernet
                        && ip_version == 4'h4
                        && ip_header_length == 4'h5
                        && (fragmentation & 16'h3FFF) == 16'h0000
                        && protocol == 8'h11
                        && ok_checksum;
        end
    end

    

endmodule

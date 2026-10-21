module ip_ethernet_wrapper #(parameter BEAT_SIZE = 64) (
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
    output reg valid_ethernet_header,

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

    output valid_ip,
    output reg ok_ip
);
    wire [BEAT_SIZE-1:0] s_axis_ip_tdata;
    wire [7:0] s_axis_ip_tkeep;
    wire s_axis_ip_tlast;
    wire s_axis_ip_tvalid;
    wire s_axis_ip_tready;

    ethernet_header_extractor #(.BEAT_SIZE(BEAT_SIZE)) ethernet_header_extractor_dut (
        .clk(clk),
        .reset(reset),

        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),

        .m_axis_tdata(s_axis_ip_tdata),
        .m_axis_tkeep(s_axis_ip_tkeep),
        .m_axis_tlast(s_axis_ip_tlast),
        .m_axis_tvalid(s_axis_ip_tvalid),
        .m_axis_tready(s_axis_ip_tready),

        .destination_MAC(destination_MAC),
        .source_MAC(source_MAC),
        .ether_type(ether_type),
        .valid_header(valid_ethernet_header)
    );

    ip_header_extractor #(.BEAT_SIZE(BEAT_SIZE)) ip_header_extractor_dut (
        .clk(clk),
        .reset(reset),

        .s_axis_tdata(s_axis_ip_tdata),
        .s_axis_tkeep(s_axis_ip_tkeep),
        .s_axis_tlast(s_axis_ip_tlast),
        .s_axis_tvalid(s_axis_ip_tvalid),
        .s_axis_tready(s_axis_ip_tready),

        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),

        .valid_ethernet_header(valid_ethernet_header),
        .ether_type(ether_type),

        .ip_version(ip_version),
        .ip_header_length(ip_header_length),
        .differentiated_service_field(differentiated_service_field),

        .ip_udp_payload_length(ip_udp_payload_length),
        .identification(identification),
        .fragmentation(fragmentation),
        .time_to_live(time_to_live),
        .protocol(protocol),

        .header_checksum(header_checksum),
        .source_ip_address(source_ip_address),
        .destination_ip_address(destination_ip_address),

        .valid_ip(valid_ip),
        .ok_ip(ok_ip)
    );

endmodule

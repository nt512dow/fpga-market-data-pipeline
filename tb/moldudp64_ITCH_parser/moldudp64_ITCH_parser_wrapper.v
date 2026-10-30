module moldudp64_ITCH_parser_wrapper #(parameter BEAT_SIZE = 64, PORT = 16'h5678) (
    input clk, 
    input reset,

    input [BEAT_SIZE-1:0] s_axis_tdata,
    input [7:0] s_axis_tkeep,
    input s_axis_tlast,
    input s_axis_tvalid,

    output s_axis_tready,


    output [47:0] destination_MAC,
    output [47:0] source_MAC,
    output [15:0] ether_type,
    output valid_ethernet_header,

    output [3:0] ip_version,
    output [3:0] ip_header_length,
    output [7:0] differentiated_service_field,

    output [15:0] ip_udp_payload_length,
    output [15:0] identification,
    output [15:0] fragmentation,
    output [7:0] time_to_live,
    output [7:0] protocol,

    output [15:0] header_checksum,
    output [31:0] source_ip_address,
    output [31:0] destination_ip_address,

    output valid_ip,
    output ok_ip,

    output [15:0] source_port,
    output [15:0] destination_port,
    output [15:0] udp_length,
    output [15:0] udp_checksum,
    output valid_udp,
    output ok_udp,

    output [79:0] session,
    output [63:0] sequence_no,
    output [15:0] message_count,

    output valid_header,
    output valid_message,

    output known_and_correct_length,

    output [7:0] message_type,

    output [15:0] stock_locate,
    output [15:0] tracking_number,
    output [47:0] timestamp,
    output [63:0] order_reference_number,
    output [7:0] buy_sell_indicator,
    output [31:0] shares,
    output [63:0] stock,
    output [31:0] price,

    output [31:0] executed_shares,
    output [63:0] match_number,

    output [31:0] cancelled_shares
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

    wire [BEAT_SIZE-1:0] s_axis_udp_tdata;
    wire [7:0] s_axis_udp_tkeep;
    wire s_axis_udp_tlast;
    wire s_axis_udp_tvalid;
    wire s_axis_udp_tready;

    ip_header_extractor #(.BEAT_SIZE(BEAT_SIZE)) ip_header_extractor_dut (
        .clk(clk),
        .reset(reset),

        .s_axis_tdata(s_axis_ip_tdata),
        .s_axis_tkeep(s_axis_ip_tkeep),
        .s_axis_tlast(s_axis_ip_tlast),
        .s_axis_tvalid(s_axis_ip_tvalid),
        .s_axis_tready(s_axis_ip_tready),

        .m_axis_tdata(s_axis_udp_tdata),
        .m_axis_tkeep(s_axis_udp_tkeep),
        .m_axis_tlast(s_axis_udp_tlast),
        .m_axis_tvalid(s_axis_udp_tvalid),
        .m_axis_tready(s_axis_udp_tready),

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

    wire [BEAT_SIZE-1:0] s_axis_realigner_tdata;
    wire [7:0] s_axis_realigner_tkeep;
    wire s_axis_realigner_tlast;
    wire s_axis_realigner_tvalid;
    wire s_axis_realigner_tready;

    udp_header_extractor #(.BEAT_SIZE(BEAT_SIZE), .PORT(PORT)) udp_header_extractor_dut (
        .clk(clk),
        .reset(reset),

        .s_axis_tdata(s_axis_udp_tdata),
        .s_axis_tkeep(s_axis_udp_tkeep),
        .s_axis_tlast(s_axis_udp_tlast),
        .s_axis_tvalid(s_axis_udp_tvalid),
        .s_axis_tready(s_axis_udp_tready),

        .m_axis_tdata(s_axis_realigner_tdata),
        .m_axis_tkeep(s_axis_realigner_tkeep),
        .m_axis_tlast(s_axis_realigner_tlast),
        .m_axis_tvalid(s_axis_realigner_tvalid),
        .m_axis_tready(s_axis_realigner_tready),

        .ok_ip(ok_ip),
        .valid_ip(valid_ip),
        .ip_udp_payload_length(ip_udp_payload_length),

        .source_port(source_port),
        .destination_port(destination_port),
        .udp_length(udp_length),
        .checksum(udp_checksum),
        .valid_udp(valid_udp),
        .ok_udp(ok_udp)
    );

    wire [BEAT_SIZE-1:0] s_axis_moldudp64_ITCH_parser_tdata;
    wire [7:0] s_axis_moldudp64_ITCH_parser_tkeep;
    wire s_axis_moldudp64_ITCH_parser_tlast;
    wire s_axis_moldudp64_ITCH_parser_tvalid;
    wire s_axis_moldudp64_ITCH_parser_tready;
    wire s_axis_moldudp64_ITCH_parser_tuser;

    realigner #(.BEAT_SIZE(BEAT_SIZE)) realigner_dut (
        .clk(clk),
        .reset(reset),

        .s_axis_tdata(s_axis_realigner_tdata),
        .s_axis_tkeep(s_axis_realigner_tkeep),
        .s_axis_tlast(s_axis_realigner_tlast),
        .s_axis_tvalid(s_axis_realigner_tvalid),
        .s_axis_tready(s_axis_realigner_tready),

        .m_axis_tdata(s_axis_moldudp64_ITCH_parser_tdata),
        .m_axis_tkeep(s_axis_moldudp64_ITCH_parser_tkeep),
        .m_axis_tlast(s_axis_moldudp64_ITCH_parser_tlast),
        .m_axis_tvalid(s_axis_moldudp64_ITCH_parser_tvalid),
        .m_axis_tready(s_axis_moldudp64_ITCH_parser_tready),
        .m_axis_tuser(s_axis_moldudp64_ITCH_parser_tuser),

        .ok_udp(ok_udp),
        .valid_udp(valid_udp)
    );

    wire [511:0] message_data;
    wire [15:0] message_length;
    

    moldudp64_ITCH_parser #(.BEAT_SIZE(BEAT_SIZE)) moldudp64_ITCH_parser_dut (
        .clk(clk),
        .reset(reset),

        .s_axis_tdata(s_axis_moldudp64_ITCH_parser_tdata),
        .s_axis_tkeep(s_axis_moldudp64_ITCH_parser_tkeep),
        .s_axis_tlast(s_axis_moldudp64_ITCH_parser_tlast),
        .s_axis_tvalid(s_axis_moldudp64_ITCH_parser_tvalid),
        .s_axis_tready(s_axis_moldudp64_ITCH_parser_tready),
        .s_axis_tuser(s_axis_moldudp64_ITCH_parser_tuser),

        .session(session),
        .sequence_no(sequence_no),
        .message_count(message_count),

        .message_length(message_length),
        .message_data(message_data),

        .ok_udp(ok_udp),
        .valid_udp(valid_udp),

        .valid_message(valid_message),
        .valid_header(valid_header)
    );

    message_extractor message_extractor_dut (
        .message_data(message_data),
        .message_length(message_length),
        .known_and_correct_length(known_and_correct_length),

        .message_type(message_type),

        .stock_locate(stock_locate),
        .tracking_number(tracking_number),
        .timestamp(timestamp),
        .order_reference_number(order_reference_number),
        .buy_sell_indicator(buy_sell_indicator),
        .shares(shares),
        .stock(stock),
        .price(price),

        .executed_shares(executed_shares),
        .match_number(match_number),

        .cancelled_shares(cancelled_shares)
    );

endmodule
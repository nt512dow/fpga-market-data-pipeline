module moldudp64_ITCH_parser #(parameter BEAT_SIZE=64) (
    input clk,
    input reset,

    input [BEAT_SIZE-1:0] s_axis_tdata,
    input [7:0] s_axis_tkeep,
    input s_axis_tlast,
    input s_axis_tvalid,
    input s_axis_tuser,
    output s_axis_tready,

    output reg [79:0] session,
    output reg [63:0] sequence_no,
    output reg [15:0] message_count,

    output reg [15:0] message_length,
//    output reg [7:0] message_type,
    output reg [511:0] message_data, //accumulator to store the message

    input ok_udp,
    input valid_udp,

    output reg valid_message,
    output reg valid_header
);
// a 512-bit gearbox that allows us to overcome the alignment problem 
// new data always gets put on top of old data
// we always read from 0
// we allow the data to accumulate till we have enough to read what we need


assign s_axis_tready = 1'b1; //buffer cannot overflow because maximum message length is 50 bytes
wire transfer_happening;
assign transfer_happening = s_axis_tready && s_axis_tvalid;

//helper functions
function [15:0] swap_16(input [15:0] v);
    swap_16 = {v[7:0], v[15:8]};
endfunction
function [63:0] swap_64(input [63:0] v);
    swap_64 = {v[7:0],v[15:8],v[23:16],v[31:24],v[39:32],
                v[47:40],v[55:48],v[63:56]};
endfunction
function [79:0] swap_80(input [79:0] v);
    swap_80 = {v[7:0],v[15:8],v[23:16],v[31:24],v[39:32],
                 v[47:40],v[55:48],v[63:56],v[71:64],v[79:72]};
endfunction
function [3:0] nbytes(input [7:0] k);
    nbytes = k[0]+k[1]+k[2]+k[3]+k[4]+k[5]+k[6]+k[7];
endfunction
function [63:0] keep_mask_64(input [7:0] k);
    reg [3:0] j;
    for (j = 0; j < 8; j = j + 1) begin 
        keep_mask_64[8*j +: 8] = {8{k[j]}};
    end
endfunction

//gearbox
reg [511:0] data_buffer; //bytes above byte count are always 0
reg [9:0] buffer_byte_count;
reg [9:0] bytes_consumed;

wire [3:0] received_bytes = transfer_happening ? nbytes(s_axis_tkeep) : 4'd0;
wire [63:0] received_data = transfer_happening ? (s_axis_tdata & keep_mask_64(s_axis_tkeep)) : 64'd0;
wire [9:0] total_byte_count = received_bytes + buffer_byte_count;
wire [511:0] total_data_buffer = data_buffer | {448'd0, received_data} << {buffer_byte_count, 3'b000};

//fsm
localparam HEADER = 2'b00,
MESSAGE = 2'b01,
DRAIN = 2'b10;

reg [1:0] current_state;

wire header_done = (current_state == HEADER) && (total_byte_count >= 10'd20);

wire [15:0] message_length_field = swap_16(total_data_buffer[15:0]);
wire message_length_available = (total_byte_count >= 2);
wire ok_message_length = (message_length_field != 0) && (message_length_field <= 50);
wire [6:0] total_message_length = message_length_field[6:0] + 2;
wire message_done = (current_state == MESSAGE) && (total_byte_count >= total_message_length) && message_length_available && ok_message_length;


always @(*) begin 
    bytes_consumed = 0;
    if (header_done) bytes_consumed = 10'd20;
    else if (message_done) bytes_consumed = total_message_length;
    else if (current_state == DRAIN) bytes_consumed = total_byte_count;
end


reg ok_frame;
wire verdict_now = transfer_happening && valid_udp && ok_udp;
initial ok_frame = 0;
always @(posedge clk) begin
    if (reset) ok_frame <= 0;
    else begin
        if (verdict_now) ok_frame <= 1; //we hold this flag till tlast 
        if (s_axis_tlast && transfer_happening) ok_frame <= 0;
    end
end


reg [15:0] messages_remaining;

always @(posedge clk) begin
    valid_message <= 0;
    valid_header <= 0;

    if (reset) begin
        current_state <= HEADER;
        data_buffer <= 0;
        buffer_byte_count <= 0;
        messages_remaining <= 16'd0;
 
        session <= 80'd0;
        sequence_no <= 64'd0;
        message_count <= 16'd0;
        message_length <= 16'd0;
        message_data <= 512'd0;
    end else begin
        buffer_byte_count <= total_byte_count - bytes_consumed;
        data_buffer <= total_data_buffer >> {bytes_consumed, 3'b000};

        case (current_state)
            HEADER: begin
                if (header_done) begin
                    session <= swap_80(total_data_buffer[0 +: 80]);
                    sequence_no <= swap_64(total_data_buffer[80 +: 64]);
                    message_count <= swap_16(total_data_buffer[144 +: 16]);
                    messages_remaining <= swap_16(total_data_buffer[144 +: 16]);
                    valid_header <= 1; //valid_header goes high for exactly 1 clock cycle
                    current_state <= (total_data_buffer[144 +: 16] == 16'd0 ||
                                 total_data_buffer[144 +: 16] == 16'hFFFF) ? DRAIN : MESSAGE;
                end
            end
            MESSAGE: begin
                if (message_length_available && !ok_message_length) begin
                    current_state <= DRAIN;
                end else if (message_done) begin 
                    valid_message <= (ok_frame || verdict_now); //just in case ok_frame is meant to rise this cycle
                                                                // valid message goes high for exactly 1 clock cycle
                    message_length <= message_length_field;
                    message_data <= {112'b0, total_data_buffer[16 +: 400]}; //just add the maximum length possible, the rest are 0 anyway
                    messages_remaining <= messages_remaining-1;
                    if (messages_remaining == 1) begin
                        current_state <= DRAIN;
                    end
                end
            end
            DRAIN: ;
        endcase
        if (transfer_happening && s_axis_tlast) begin
            current_state <= HEADER;
            data_buffer <= 0;
            buffer_byte_count <= 0;
            messages_remaining <= 0;
        end
    end
end

endmodule

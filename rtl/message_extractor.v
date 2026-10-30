module message_extractor (
    input [511:0] message_data,
    input [15:0] message_length,

    output known_and_correct_length,
    

    //every ITCH message has [message_type, stock_locate, tracking_number, timestamp] as header

    output [7:0] message_type,

    //A, add order message
    output [15:0] stock_locate,
    output [15:0] tracking_number,
    output [47:0] timestamp,
    output [63:0] order_reference_number,
    output [7:0] buy_sell_indicator,
    output [31:0] shares,
    output [63:0] stock,
    output [31:0] price,


    //E, order executed message
    //stock_locate
    //tracking_number
    //timestamp
    //order_reference_number
    output [31:0] executed_shares,
    output [63:0] match_number,

    //X, order cancel message
    //stock_locate
    //tracking_number
    //timestamp
    //order_reference_number
    output [31:0] cancelled_shares


);
// sorting out the message_data into their relevant fields
// for message type A, E, X

assign message_type = message_data[7:0];
assign known_and_correct_length = (message_type == "A" && message_length == 36) ||
                                  (message_type == "E" && message_length == 31) ||
                                  (message_type == "X" && message_length == 23);

//these functions should be called with fixed j
function [15:0] swap_16_index(input [511:0] message_data, input integer j);
    swap_16_index = {message_data[j*8 +: 8], message_data[(j+1)*8 +: 8]};
endfunction
function [31:0] swap_32_index(input [511:0] message_data, input integer j);
    swap_32_index = {swap_16_index(message_data, j), swap_16_index(message_data, j+2)};
endfunction
function [63:0] swap_64_index(input [511:0] message_data, input integer j);
    swap_64_index = {swap_32_index(message_data, j), swap_32_index(message_data, j+4)};
endfunction

//common fields for all messages
assign stock_locate = swap_16_index(message_data, 1);
assign tracking_number = swap_16_index(message_data, 3);
assign timestamp = {swap_32_index(message_data, 5), swap_16_index(message_data, 9)};

//A
assign order_reference_number = swap_64_index(message_data, 11);
assign buy_sell_indicator = message_data[159:152];
assign shares = swap_32_index(message_data, 20);
assign stock = swap_64_index(message_data, 24);
assign price = swap_32_index(message_data, 32);

//E
assign executed_shares = swap_32_index(message_data, 19);
assign match_number = swap_64_index(message_data, 23);

//X
assign cancelled_shares = swap_32_index(message_data, 19);

endmodule

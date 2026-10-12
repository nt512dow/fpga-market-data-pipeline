module skid_buffer #(parameter DATA_WIDTH = 8, OPT_LOWPOWER = 0, OPT_OUTREG = 0) (
    input i_valid,
    input [DATA_WIDTH-1:0] i_data,
    output o_ready,

    output o_valid, 
    output [DATA_WIDTH-1:0] o_data,
    input i_ready,

    input i_reset, 
    input clk
);
    reg r_valid;
    reg [DATA_WIDTH-1:0] r_data;
    
    initial r_valid = 0;
    always @(posedge clk) begin
        if (i_reset) begin 
            r_valid <= 0;
        end else if ((i_valid && o_ready) && (o_valid && !i_ready)) begin 
            //stalled because of i_ready
            r_valid <= 1;
        end else if (i_ready) begin 
            r_valid <= 0;
        end
    end

    initial r_data = 0; //in this implementation, the input is always registered
    always @(posedge clk) begin
        if (i_reset) begin 
            r_data <= 0;
        end else if (OPT_LOWPOWER && (!o_valid || i_ready)) begin
            r_data <= 0;
        end else if ((!OPT_LOWPOWER || i_valid) && o_ready) begin
            r_data <= i_data;
        end
    end

    assign o_ready = !r_valid; //if the buffer is empty, we can accept a beat

    //o_valid and o_data
    generate
    if (!OPT_OUTREG) begin: combinational_output
        assign o_valid = (i_valid || r_valid); //if there's valid data to send out

        assign o_data = (r_valid) ? r_data :
                        (!OPT_LOWPOWER || i_valid) ? i_data : 0;

    end else begin: registered_output
        reg clocked_valid;
        reg [DATA_WIDTH-1:0] clocked_data;

        initial clocked_valid = 0;
        always @(posedge clk) begin
            if (i_reset) begin
                clocked_valid <= 0;
            end else if (!o_valid || i_ready) begin 
                /*
                this condition ensures that o_valid changes together with o_data
                prevents o_valid from changing from 1 --> 0 whilst not transmitting data 
                prevents violation of AXI protocol
                */
                clocked_valid <= (i_valid || r_valid);
            end
        end

        initial clocked_data = 0;
        always @(posedge clk) begin
            if (OPT_LOWPOWER && i_reset) begin
                clocked_data <= 0;
            end else if (!o_valid || i_ready) begin
                /*
                this condition prevents losing of the stalled beat
                that is to be currently transmitted on o_data
                */

                if (r_valid) begin 
                    clocked_data <= r_data;
                end else if (!OPT_LOWPOWER || i_valid) begin
                    clocked_data <= i_data;
                end else begin
                    clocked_data <= 0;
                end 
            end

        end

        assign o_valid = clocked_valid;
        assign o_data = clocked_data;
    end
    endgenerate

endmodule

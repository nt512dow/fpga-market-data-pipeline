module realigner #(parameter BEAT_SIZE = 64) (
    input clk,
    input reset,

    input [BEAT_SIZE-1:0] s_axis_tdata,
    input [7:0] s_axis_tkeep,
    input s_axis_tlast,
    input s_axis_tvalid,
    output s_axis_tready,

    output reg [BEAT_SIZE-1:0] m_axis_tdata,
    output reg [7:0] m_axis_tkeep,
    output reg m_axis_tlast,
    output reg m_axis_tvalid,
    output reg m_axis_tuser,
    input m_axis_tready,

    input ok_udp,
    input valid_udp
);
// contract: we strip away all headers, keeping only the payload
// we shift the payload bytes to the correct lanes, with the most signifcant byte at lane 0
// we need to wait for beat 7 to confirm that all headers are fine, we then set m_axis_tuser = !(ok_udp && valid_udp) on tlast
// downstream to discard if m_axis_tuser = 1 on tlast
// we assume a minimum payload of 20 bytes as per MoldUDP64, so packet will end later than beat 6
// valid_udp and ok_udp are both required because of stale state: if ok_udp == 0, we don't know if the verdict is not out yet or if it is actually a bad beat

    wire out_free;
    wire transfer_happening;
    reg flush_pending;
    reg [2:0] beat_count;


    assign out_free = (!m_axis_tvalid || m_axis_tready); //output free if slave is ready or i am not trying to send, in this case the input will be registered
    assign s_axis_tready = out_free && !flush_pending; //have to wait for flush beat
    assign transfer_happening = s_axis_tready && s_axis_tvalid;

    wire need_flush;
    assign need_flush = s_axis_tlast && s_axis_tkeep > 8'b00000011; //we require a flush beat if there is overflow 

    reg [47:0] flush_data;
    reg [5:0] flush_keep;
    reg [63:0] previous_data;

    initial begin
        m_axis_tdata = 0;
        m_axis_tkeep = 0;
        m_axis_tvalid = 0;
        m_axis_tlast = 0;
        m_axis_tuser = 0;
        flush_data = 0;
        flush_keep = 0;
        flush_pending = 0;
    end
    always @(posedge clk) begin
        if (reset) begin
            m_axis_tdata <= 0;
            m_axis_tkeep <= 0;
            m_axis_tvalid <= 0;
            m_axis_tlast <= 0;
            m_axis_tuser <= 0;
            flush_data <= 0;
            flush_keep <= 0;
            flush_pending <= 0;
        end else begin
            if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 0; //default case: we can transmit the beat so we set it to 0 on the next cycle
            end

            if (flush_pending && out_free) begin
            //send the flush beat
                m_axis_tdata <= {16'b0, flush_data};
                m_axis_tkeep <= {2'b00, flush_keep};
                m_axis_tvalid <= 1; //overwrites m_axis_tvalid
                m_axis_tlast <= 1;
                m_axis_tuser <= !(valid_udp && ok_udp); //attach tuser on the last beat, 1 indicates an error and to discard the beat
                flush_pending <= 0;
            end else if (transfer_happening && beat_count >= 6) begin //front of payload on beat 5 loaded into previous data, then on beat 6 we can access it, safe as payload is min 20 bytes
                m_axis_tdata <= {s_axis_tdata[15:0], previous_data[63:16]};
                m_axis_tkeep <= {s_axis_tkeep[1:0], 6'b111111};
                m_axis_tvalid <= 1; //overwrites m_axis_tvalid
                m_axis_tlast <= !need_flush && s_axis_tlast;
                m_axis_tuser <= !need_flush && s_axis_tlast && !(valid_udp && ok_udp);
                if (need_flush) begin
                    flush_data <= s_axis_tdata[63:16];
                    flush_keep <= s_axis_tkeep[7:2];
                    flush_pending <= 1;
                end
            end
        end
    end

    initial beat_count = 0;
    always @(posedge clk) begin
        if (reset) begin
            beat_count <= 0;
        end else if (transfer_happening) begin 
            if (s_axis_tlast) begin
                beat_count <= 0;
            end else if (beat_count <= 6) begin 
            //beat_count saturates at 7
                beat_count <= beat_count + 1;
            end
        end 
    end

    initial previous_data = 0;
    always @(posedge clk) begin
        if (reset) begin
            previous_data <= 0;
        end else if (transfer_happening) begin 
            previous_data <= s_axis_tdata;
        end
    end


endmodule

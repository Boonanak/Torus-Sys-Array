`timescale 1ns / 1ps

module i2c_controller(
    input wire clk,
    input wire rst,
    input wire [6:0] addr,
    input wire [15:0] data_in,
    input wire enable,
    input wire rw,

    output reg [15:0] data_out,
    output wire ready,

    inout wire i2c_sda,
    inout wire i2c_scl
);

    localparam IDLE        = 0;
    localparam START       = 1;
    localparam ADDRESS     = 2;
    localparam READ_ACK    = 3;
    localparam WRITE_DATA  = 4;
    localparam WRITE_ACK2  = 5;
    localparam READ_DATA   = 6;
    localparam WRITE_ACK   = 7;
    localparam STOP        = 8;

    localparam DIVIDE_BY = 125;

    reg [7:0] state;
    reg [7:0] saved_addr;
    reg [7:0] counter;
    reg [7:0] counter2 = 0;

    reg write_enable;
    reg sda_out;

    reg i2c_scl_enable = 0;
    reg i2c_clk = 1;

    // 0 = upper byte, 1 = lower byte
    reg byte_sel;

    assign ready =
        ((rst == 0) && (state == IDLE)) ? 1'b1 : 1'b0;

    assign i2c_scl =
        (i2c_scl_enable == 0) ? 1'b1 : i2c_clk;

    assign i2c_sda =
        (write_enable == 1) ? sda_out : 1'bz;

    //--------------------------------------------------
    // CLOCK DIVIDER
    //--------------------------------------------------

    always @(posedge clk) begin
        if(counter2 == (DIVIDE_BY/2)-1) begin
            i2c_clk <= ~i2c_clk;
            counter2 <= 0;
        end
        else begin
            counter2 <= counter2 + 1;
        end
    end

    //--------------------------------------------------
    // SCL CONTROL
    //--------------------------------------------------

    always @(negedge i2c_clk or posedge rst) begin

        if(rst) begin
            i2c_scl_enable <= 0;
        end
        else begin
            if(state == IDLE ||
               state == START ||
               state == STOP)
                i2c_scl_enable <= 0;
            else
                i2c_scl_enable <= 1;
        end

    end

    //--------------------------------------------------
    // MAIN FSM
    //--------------------------------------------------

    always @(posedge i2c_clk or posedge rst) begin

        if(rst) begin
            state <= IDLE;
            byte_sel <= 0;
        end
        else begin

            case(state)

                //--------------------------------------
                IDLE:
                //--------------------------------------
                begin
                    if(enable) begin
                        saved_addr <= {addr,rw};
                        byte_sel <= 0;
                        state <= START;
                    end
                end

                //--------------------------------------
                START:
                //--------------------------------------
                begin
                    counter <= 7;
                    state <= ADDRESS;
                end

                //--------------------------------------
                ADDRESS:
                //--------------------------------------
                begin
                    if(counter == 0)
                        state <= READ_ACK;
                    else
                        counter <= counter - 1;
                end

                //--------------------------------------
                READ_ACK:
                //--------------------------------------
                begin
                    if(i2c_sda == 0) begin

                        counter <= 7;
                        byte_sel <= 0;

                        if(saved_addr[0] == 0)
                            state <= WRITE_DATA;
                        else
                            state <= READ_DATA;

                    end
                    else begin
                        state <= STOP;
                    end
                end

                //--------------------------------------
                WRITE_DATA
                //--------------------------------------
                begin

                    if(counter == 0)
                        state <= WRITE_ACK2;
                    else
                        counter <= counter - 1;

                end

                //--------------------------------------
                WRITE_ACK2
                //--------------------------------------
                begin

                    if(i2c_sda == 0) begin

                        if(byte_sel == 0) begin
                            byte_sel <= 1;
                            counter <= 7;
                            state <= WRITE_DATA;
                        end
                        else begin
                            state <= IDLE;
                        end

                    end
                    else begin
                        state <= STOP;
                    end

                end

                //--------------------------------------
                READ_DATA
                //--------------------------------------
                begin

                    if(byte_sel == 0)
                        data_out[counter + 8] <= i2c_sda;
                    else
                        data_out[counter] <= i2c_sda;

                    if(counter == 0)
                        state <= WRITE_ACK;
                    else
                        counter <= counter - 1;

                end

                //--------------------------------------
                WRITE_ACK
                //--------------------------------------
                begin

                    if(byte_sel == 0) begin
                        byte_sel <= 1;
                        counter <= 7;
                        state <= READ_DATA;
                    end
                    else begin
                        state <= STOP;
                    end

                end

                //--------------------------------------
                STOP
                //--------------------------------------
                begin
                    state <= IDLE;
                end

            endcase

        end

    end

    //--------------------------------------------------
    // SDA OUTPUT CONTROL
    //--------------------------------------------------

    always @(negedge i2c_clk or posedge rst) begin

        if(rst) begin

            write_enable <= 1;
            sda_out <= 1;

        end
        else begin

            case(state)

                //--------------------------------------
                START
                //--------------------------------------
                begin
                    write_enable <= 1;
                    sda_out <= 0;
                end

                //--------------------------------------
                ADDRESS
                //--------------------------------------
                begin
                    write_enable <= 1;
                    sda_out <= saved_addr[counter];
                end

                //--------------------------------------
                READ ACK
                //--------------------------------------
                begin
                    write_enable <= 0;
                end

                //--------------------------------------
                WRITE DATA
                //--------------------------------------
                begin

                    write_enable <= 1;

                    if(byte_sel == 0)
                        sda_out <= data_in[counter+8];
                    else
                        sda_out <= data_in[counter];

                end

                //--------------------------------------
                SECOND ACK FROM SLAVE
                //--------------------------------------
                begin
                    write_enable <= 0;
                end

                //--------------------------------------
                READ DATA
                //--------------------------------------
                begin
                    write_enable <= 0;
                end

                //--------------------------------------
                MASTER ACK/NACK
                //--------------------------------------
                begin

                    write_enable <= 1;

                    if(byte_sel == 0)
                        sda_out <= 0;  // ACK
                    else
                        sda_out <= 1;  // NACK

                end

                //--------------------------------------
                STOP
                //--------------------------------------
                begin
                    write_enable <= 1;
                    sda_out <= 1;
                end

            endcase

        end

    end

endmodule
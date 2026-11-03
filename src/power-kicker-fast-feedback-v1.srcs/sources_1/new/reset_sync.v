`timescale 1ns / 1ps

// Assert immediately, but release only after STAGES edges of the local clock.
// Use one instance per clock domain so a stopped clock cannot release reset.
module reset_sync #(
    parameter integer STAGES = 2
)(
    input  wire clk,
    input  wire arst_n,
    output wire rst_n
);
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [STAGES-1:0] release_pipe = {STAGES{1'b0}};

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n)
            release_pipe <= {STAGES{1'b0}};
        else
            release_pipe <= (release_pipe << 1) | {{(STAGES-1){1'b0}}, 1'b1};
    end

    assign rst_n = release_pipe[STAGES-1];
endmodule

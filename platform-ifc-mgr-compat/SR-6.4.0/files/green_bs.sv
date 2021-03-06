//
// platform_if.vh defines many required components, including both top-level
// SystemVerilog interfaces and the platform/AFU configuration parameters
// required to match the interfaces offered by the platform to the needs
// of the AFU. It is part of the platform database and imported using
// state generated by afu_platform_config.
//
// Most preprocessor variables used in this file come from this.
//
`include "platform_if.vh"

`include "pr_hssi_if.vh"
import hssi_eth_pkg::*;

parameter CCIP_TXPORT_WIDTH = $bits(t_if_ccip_Tx); 
parameter CCIP_RXPORT_WIDTH = $bits(t_if_ccip_Rx);

module green_bs
(
    // CCI-P Interface
    input   logic                         Clk_400,             // Core clock. CCI interface is synchronous to this clock.
    input   logic                         Clk_200,             // Core clock. CCI interface is synchronous to this clock.
    input   logic                         Clk_100,             // Core clock. CCI interface is synchronous to this clock.
    input   logic                         uClk_usr,             
    input   logic                         uClk_usrDiv2,         
    input   logic                         SoftReset,           // CCI interface reset. The Accelerator IP must use this Reset. ACTIVE HIGH
    input   logic [1:0]                   pck_cp2af_pwrState,
    input   logic                         pck_cp2af_error,
    output  logic [CCIP_TXPORT_WIDTH-1:0] bus_ccip_Tx,         // CCI-P TX port
    input   logic [CCIP_RXPORT_WIDTH-1:0] bus_ccip_Rx,         // CCI-P RX port
   
    // JTAG Interface for PR region debug
    input   logic            sr2pr_tms,
    input   logic            sr2pr_tdi,             
    output  logic            pr2sr_tdo,             
    input   logic            sr2pr_tck,
    input   logic            sr2pr_tckena,
   
    pr_hssi_if.to_fiu        hssi,
    
    output  [4:0] g2b_GPIO_a         ,// GPIO port A
    output  [4:0] g2b_GPIO_b         ,// GPIO port B
    output        g2b_I2C0_scl       ,// I2C0 clock
    output        g2b_I2C0_sda       ,// I2C0 data
    output        g2b_I2C0_rstn      ,// I2C0 rstn
    output        g2b_I2C1_scl       ,// I2C1 clock
    output        g2b_I2C1_sda       ,// I2C1 data
    output        g2b_I2C1_rstn      ,// I2C1 rstn

    input   [4:0] b2g_GPIO_a         ,// GPIO port A
    input   [4:0] b2g_GPIO_b         ,// GPIO port B
    input         b2g_I2C0_scl       ,// I2C0 clock
    input         b2g_I2C0_sda       ,// I2C0 data
    input         b2g_I2C0_rstn      ,// I2C0 rstn
    input         b2g_I2C1_scl       ,// I2C1 clock
    input         b2g_I2C1_sda       ,// I2C1 data
    input         b2g_I2C1_rstn      ,// I2C1 rstn

    output  [4:0] oen_GPIO_a         ,// GPIO port A
    output  [4:0] oen_GPIO_b         ,// GPIO port B
    output        oen_I2C0_scl       ,// I2C0 clock
    output        oen_I2C0_sda       ,// I2C0 data
    output        oen_I2C0_rstn      ,// I2C0 rstn
    output        oen_I2C1_scl       ,// I2C1 clock
    output        oen_I2C1_sda       ,// I2C1 data
    output        oen_I2C1_rstn       // I2C1 rstn
);

t_if_ccip_Tx af2cp_sTxPort;
t_if_ccip_Rx cp2af_sRxPort;

always_comb
begin
  bus_ccip_Tx      = af2cp_sTxPort;
  cp2af_sRxPort    = bus_ccip_Rx;
end

// ===========================================
// AFU - Remote Debug JTAG IP instantiation
// ===========================================

    wire loopback;
    sld_virtual_jtag 
    inst_sld_virtual_jtag (
          .tdi (loopback), 
          .tdo (loopback)
    );
    
    // Q17.0 modified SCJIO
    // with tck_ena   
    altera_sld_host_endpoint#(
        .NEGEDGE_TDO_LATCH(0),
        .USE_TCK_ENA(1)
    ) scjio
    (
        .tck         (sr2pr_tck),         //  jtag.tck
        .tck_ena     (sr2pr_tckena),      //      .tck_ena
        .tms         (sr2pr_tms),         //      .tms
        .tdi         (sr2pr_tdi),         //      .tdi
        .tdo         (pr2sr_tdo),         //      .tdo
                     
        .vir_tdi     (sr2pr_tdi),         //      .vir_tdi
        .select_this (1'b1)               //      .select_this
    );
      
// ===========================================
// CCIP_STD_AFU Instantiation 
// ===========================================

    // Instantiate either a shim or the AFU
    `PLATFORM_SHIM_MODULE_NAME `PLATFORM_SHIM_MODULE_NAME(
        .pClk               (Clk_400),         // 16ui link/protocol clock domain. Interface Clock
        .pClkDiv2           (Clk_200),         // 32ui link/protocol clock domain. Synchronous to interface clock
        .pClkDiv4           (Clk_100),         // 64ui link/protocol clock domain. Synchronous to interface clock
        .uClk_usr           (uClk_usr),
        .uClk_usrDiv2       (uClk_usrDiv2),
        .pck_cp2af_softReset(SoftReset),
`ifdef AFU_TOP_REQUIRES_POWER_2BIT
        .pck_cp2af_pwrState (pck_cp2af_pwrState),
`endif
`ifdef AFU_TOP_REQUIRES_ERROR_1BIT
        .pck_cp2af_error    (pck_cp2af_error),                   
`endif

`ifdef AFU_TOP_REQUIRES_HSSI_RAW_PR
        // HSSI as a raw connection.  The AFU must instantiate a MAC.
        .hssi                   (hssi),
`endif

        .pck_af2cp_sTx      (af2cp_sTxPort),   // CCI-P Tx Port
        .pck_cp2af_sRx      (cp2af_sRxPort)    // CCI-P Rx Port
    );

// ======================================================
// Workaround: To preserve uClk_usr routing to  PR region
// ======================================================

(* noprune *) logic uClk_usr_q1, uClk_usr_q2;
(* noprune *) logic uClk_usrDiv2_q1, uClk_usrDiv2_q2;
(* noprune *) logic pClkDiv4_q1, pClkDiv4_q2;
(* noprune *) logic pClkDiv2_q1, pClkDiv2_q2;

always_ff @(posedge uClk_usr)
begin
  uClk_usr_q1     <= uClk_usr_q2;
  uClk_usr_q2     <= !uClk_usr_q1;
end

always_ff @(posedge uClk_usrDiv2)
begin
  uClk_usrDiv2_q1 <= uClk_usrDiv2_q2;
  uClk_usrDiv2_q2 <= !uClk_usrDiv2_q1;
end

always_ff @(posedge Clk_100)
begin
  pClkDiv4_q1     <= pClkDiv4_q2;
  pClkDiv4_q2     <= !pClkDiv4_q1;
end

always_ff @(posedge Clk_200)
begin
  pClkDiv2_q1     <= pClkDiv2_q2;
  pClkDiv2_q2     <= !pClkDiv2_q1;
end


//
// Tie off GPIO ports, which are never used.  Only the HSSI interface is supported.
//

// Setting up the 3rd state buffers as Inputs
assign g2b_GPIO_a    = 5'b0;
assign g2b_GPIO_b    = 5'b0;
assign g2b_I2C0_scl  = 1'b0;
assign g2b_I2C0_sda  = 1'b0;
assign g2b_I2C0_rstn = 1'b0;
assign g2b_I2C1_scl  = 1'b0;
assign g2b_I2C1_sda  = 1'b0;
assign g2b_I2C1_rstn = 1'b0;

assign oen_GPIO_a    = 5'b0;
assign oen_GPIO_b    = 5'b0;
assign oen_I2C0_scl  = 1'b0;
assign oen_I2C0_sda  = 1'b0;
assign oen_I2C0_rstn = 1'b0;
assign oen_I2C1_scl  = 1'b0;
assign oen_I2C1_sda  = 1'b0;
assign oen_I2C1_rstn = 1'b0;

(* noprune *) reg [4:0] b2g_GPIO_a_q;
(* noprune *) reg [4:0] b2g_GPIO_b_q;
(* noprune *) reg       b2g_I2C0_scl_q;
(* noprune *) reg       b2g_I2C0_sda_q;
(* noprune *) reg       b2g_I2C0_rstn_q;
(* noprune *) reg       b2g_I2C1_scl_q;
(* noprune *) reg       b2g_I2C1_sda_q;
(* noprune *) reg       b2g_I2C1_rstn_q;

always_ff @(posedge Clk_100)
begin
    b2g_GPIO_a_q    <= b2g_GPIO_a    ;
    b2g_GPIO_b_q    <= b2g_GPIO_b    ;
    b2g_I2C0_scl_q  <= b2g_I2C0_scl  ;
    b2g_I2C0_sda_q  <= b2g_I2C0_sda  ;
    b2g_I2C0_rstn_q <= b2g_I2C0_rstn ;
    b2g_I2C1_scl_q  <= b2g_I2C1_scl  ;
    b2g_I2C1_sda_q  <= b2g_I2C1_sda  ;
    b2g_I2C1_rstn_q <= b2g_I2C1_rstn ;
end

endmodule

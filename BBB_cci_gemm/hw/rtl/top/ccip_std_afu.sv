//
// Copyright (c) 2017, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

// Include MPF data types, including the CCI interface pacakge.
`include "cci_mpf_if.vh"
`define ENABLE_ASYNC


module ccip_std_afu
  (
   // CCI-P Clocks and Resets
   input logic 	     pClk, // 400MHz - CCI-P clock domain. Primary interface clock
   input logic 	     pClkDiv2, // 200MHz - CCI-P clock domain.
   input logic 	     pClkDiv4, // 100MHz - CCI-P clock domain.
   input logic 	     uClk_usr, // User clock domain. Refer to clock programming guide  ** Currently provides fixed 300MHz clock **
   input logic 	     uClk_usrDiv2, // User clock domain. Half the programmed frequency  ** Currently provides fixed 150MHz clock **
   input logic 	     pck_cp2af_softReset, // CCI-P ACTIVE HIGH Soft Reset
   input logic [1:0] pck_cp2af_pwrState, // CCI-P AFU Power State
   input logic 	     pck_cp2af_error, // CCI-P Protocol Error Detected

   // Interface structures
   input 	     t_if_ccip_Rx pck_cp2af_sRx, // CCI-P Rx Port
   output 	     t_if_ccip_Tx pck_af2cp_sTx         // CCI-P Tx Port
   );

   //=====================================================================
   // Register the interface by CCI-P 
   //=====================================================================
   
   (* noprune *) logic [1:0]  pck_cp2af_pwrState_T1;
   (* noprune *) logic		  pck_cp2af_error_T1;
   
   logic        pck_cp2af_softReset_T1;
   t_if_ccip_Rx pck_cp2af_sRx_T1;
   t_if_ccip_Tx pck_af2cp_sTx_T0;

`ifdef ENABLE_GREEN_INTERFACE_REG   
   ccip_interface_reg inst_green_ccip_interface_reg  (
    .pClk                           (pClk),
    .pck_cp2af_softReset_T0         (pck_cp2af_softReset),
    .pck_cp2af_pwrState_T0          (pck_cp2af_pwrState), 
    .pck_cp2af_error_T0             (pck_cp2af_error),    
    .pck_cp2af_sRx_T0               (pck_cp2af_sRx),      
    .pck_af2cp_sTx_T0               (pck_af2cp_sTx_T0), 
    
    .pck_cp2af_softReset_T1         (pck_cp2af_softReset_T1),
    .pck_cp2af_pwrState_T1          (pck_cp2af_pwrState_T1), 
    .pck_cp2af_error_T1             (pck_cp2af_error_T1),    
    .pck_cp2af_sRx_T1               (pck_cp2af_sRx_T1),      
    .pck_af2cp_sTx_T1               (pck_af2cp_sTx)    
);
`else
	assign pck_cp2af_pwrState_T1  = pck_cp2af_pwrState;
	assign pck_cp2af_error_T1     = pck_cp2af_error;
	assign pck_cp2af_softReset_T1 = pck_cp2af_softReset;
	assign pck_cp2af_sRx_T1       = pck_cp2af_sRx;
	assign pck_af2cp_sTx          = pck_af2cp_sTx_T0;
`endif
   
   // ====================================================================
   //  Async FIFO
   // ====================================================================
`ifdef ENABLE_ASYNC
   logic 	     afu_clk;   
   logic 	     afu_reset;   

   t_if_ccip_Tx afck_af2cp_sTx;
   t_if_ccip_Rx afck_cp2af_sRx;

 `ifdef USR_CLK
   assign afu_clk = uClk_usr;
 `else 
   assign afu_clk = pClkDiv2;
 `endif
   
   ccip_async_shim ccip_async_shim (
				    .bb_softreset   (pck_cp2af_softReset_T1),
				    .bb_clk         (pClk), 
				    .bb_tx          (pck_af2cp_sTx_T0),
				    .bb_rx          (pck_cp2af_sRx_T1),

				    .afu_softreset  (afu_reset),
				    .afu_clk        (afu_clk),
				    .afu_tx         (afck_af2cp_sTx),
				    .afu_rx         (afck_cp2af_sRx)
				    );
`endif

   // ====================================================================
   //
   //  Instantiate a memory properties factory (MPF) between the external
   //  interface and the AFU, adding support for virtual memory and
   //  control over memory ordering.
   //
   // ====================================================================

   //
   // The AFU exposes the primary AFU device feature header (DFH) at MMIO
   // address 0.  MPF defines a set of its own DFHs.  The AFU must
   // build its feature chain to point to the MPF chain.  The AFU must
   // also tell the MPF module the MMIO address at which MPF should start
   // its feature chain.
   //
   localparam MPF_DFH_MMIO_ADDR = 'h2000;

   //
   // MPF represents CCI as a SystemVerilog interface, derived from the
   // same basic types defined in ccip_if_pkg.  Interfaces reduce the
   // number of internal MPF module parameters, since each internal MPF
   // shim has a bus connected toward the AFU and a bus connected toward
   // the FIU.
   //

   //
   // Expose FIU as an MPF interface
   //
`ifdef ENABLE_ASYNC
   cci_mpf_if fiu(.clk(afu_clk));
`else 
   cci_mpf_if fiu(.clk(pClk));
`endif

   // The CCI wires to MPF mapping connections have identical naming to
   // the standard AFU.  The module exports an interface named "fiu".
   ccip_wires_to_mpf
     #(
       // All inputs and outputs in PR region (AFU) must be registered!
       .REGISTER_INPUTS(1),
       .REGISTER_OUTPUTS(1)
       )
   map_ifc(
	   // Comment out to disable async shim
`ifdef ENABLE_ASYNC
	   .pClk                   (afu_clk),
	   .pck_cp2af_softReset    (afu_reset),
	   .pck_af2cp_sTx          (afck_af2cp_sTx),
	   .pck_cp2af_sRx          (afck_cp2af_sRx),
`else
	   .pClk                   (pClk),
	   .pck_cp2af_softReset    (pck_cp2af_softReset_T1),
	   .pck_af2cp_sTx          (pck_af2cp_sTx_T0),
	   .pck_cp2af_sRx          (pck_cp2af_sRx_T1),
`endif
	   .*
	   );

   //
   // Instantiate MPF with the desired properties.
   //
`ifdef ENABLE_ASYNC
   cci_mpf_if afu(.clk(afu_clk));
`else 
   cci_mpf_if afu(.clk(pClk));
`endif

   cci_mpf
     #(
       // Should read responses be returned in the same order that
       // the reads were requested?
       .SORT_READ_RESPONSES(1),

       // Should the Mdata from write requests be returned in write
       // responses?  If the AFU is simply counting write responses
       // and isn't consuming Mdata, then setting this to 0 eliminates
       // the memory and logic inside MPF for preserving Mdata.
       .PRESERVE_WRITE_MDATA(1),

       // Enable virtual to physical translation?  When enabled, MPF
       // accepts requests with either virtual or physical addresses.
       // Virtual addresses are indicated by setting the
       // addrIsVirtual flag in the MPF extended Tx channel
       // request header.
       .ENABLE_VTP(1),

       // Enable mapping of eVC_VA to physical channels?  AFUs that both use
       // eVC_VA and read back memory locations written by the AFU must either
       // emit WrFence on VA or use explicit physical channels and enforce
       // write/read order.  Each method has tradeoffs.  WrFence VA is expensive
       // and should be emitted only infrequently.  Memory requests to eVC_VA
       // may have higher bandwidth than explicit mapping.  The MPF module for
       // physical channel mapping is optimized for each CCI platform.
       //
       // If you set ENFORCE_WR_ORDER below you probably also want to set
       // ENABLE_VC_MAP.
       //
       // The mapVAtoPhysChannel extended header bit must be set on each
       // request to enable mapping.
       .ENABLE_VC_MAP(1),
       // When ENABLE_VC_MAP is set the mapping is either static for the entire
       // run or dynamic, changing in response to traffic patterns.  The mapper
       // guarantees synchronization when the mapping changes by emitting a
       // WrFence on eVC_VA and draining all reads.  Ignored when ENABLE_VC_MAP
       // is 0.
       .ENABLE_DYNAMIC_VC_MAPPING(1),

       // Should write/write and write/read ordering within a cache
       // be enforced?  By default CCI makes no guarantees on the order
       // in which operations to the same cache line return.  Setting
       // this to 1 adds logic to filter reads and writes to ensure
       // that writes retire in order and the reads correspond to the
       // most recent write.
       //
       // ***  Even when set to 1, MPF guarantees order only within
       // ***  a given virtual channel.  There is no guarantee of
       // ***  order across virtual channels and no guarantee when
       // ***  using eVC_VA, since it spreads requests across all
       // ***  channels.  Synchronizing writes across virtual channels
       // ***  can be accomplished only by requesting a write fence on
       // ***  eVC_VA.  Syncronizing writes across virtual channels
       // ***  and then reading back the same data requires both
       // ***  requesting a write fence on eVC_VA and waiting for the
       // ***  corresponding write fence response.
       //
       .ENFORCE_WR_ORDER(0),

       // Address of the MPF feature header.  See comment above.
       .DFH_MMIO_BASE_ADDR(MPF_DFH_MMIO_ADDR)
       )
   mpf
     (
`ifdef ENABLE_ASYNC
      .clk(afu_clk),
`else
      .clk(pClk),
`endif
      .fiu,
      .afu
      );

   // ====================================================================
   //
   //  Now CCI is exposed as an MPF interface through the object named
   //  "afu".  Two primary strategies are available for connecting
   //  a design to the interface:
   //
   //    (1) Use the MPF-provided constructor functions to generate
   //        CCI request structures and pass them directly to MPF.
   //        See, for example, cci_mpf_defaultReqHdrParams() and
   //        cci_c0_genReqHdr() in cci_mpf_if_pkg.sv.
   //
   //    (1) Map "afu" back to standard CCI wires.  This is the strategy
   //        used below to map an existing AFU to MPF.
   //
   // ====================================================================

   //
   // Convert MPF interfaces back to the standard CCI structures.
   //
   t_if_ccip_Rx mpf2af_sRxPort;
   t_if_ccip_Tx af2mpf_sTxPort;

   //
   // The cci_mpf module has already registered the Rx wires heading
   // toward the AFU, so wires are acceptable.
   //
   always_comb
     begin
        mpf2af_sRxPort.c0 = afu.c0Rx;
        mpf2af_sRxPort.c1 = afu.c1Rx;

        mpf2af_sRxPort.c0TxAlmFull = afu.c0TxAlmFull;
        mpf2af_sRxPort.c1TxAlmFull = afu.c1TxAlmFull;

        afu.c0Tx = cci_mpf_cvtC0TxFromBase(af2mpf_sTxPort.c0);
        if (cci_mpf_c0TxIsReadReq(afu.c0Tx))
          begin
             // Treat all addresses as virtual.
             afu.c0Tx.hdr.ext.addrIsVirtual = 1'b1;

             // Enable eVC_VA to physical channel mapping.  This will only
             // be triggered when ENABLE_VC_MAP is set above.
             afu.c0Tx.hdr.ext.mapVAtoPhysChannel = 1'b1;

             // Enforce load/store and store/store ordering within lines.
             // This will only be triggered when ENFORCE_WR_ORDER is set.
             afu.c0Tx.hdr.ext.checkLoadStoreOrder = 1'b1;
          end

        afu.c1Tx = cci_mpf_cvtC1TxFromBase(af2mpf_sTxPort.c1);
        if (cci_mpf_c1TxIsWriteReq(afu.c1Tx))
          begin
             // Treat all addresses as virtual.
             afu.c1Tx.hdr.ext.addrIsVirtual = 1'b1;

             // Enable eVC_VA to physical channel mapping.  This will only
             // be triggered when ENABLE_VC_MAP is set above.
             afu.c1Tx.hdr.ext.mapVAtoPhysChannel = 1'b1;

             // Enforce load/store and store/store ordering within lines.
             // This will only be triggered when ENFORCE_WR_ORDER is set.
             afu.c1Tx.hdr.ext.checkLoadStoreOrder = 1'b1;
          end

        afu.c2Tx = af2mpf_sTxPort.c2;
     end

   // ====================================================================
   //  RP SGEMM 
   // ====================================================================

   gemm_top # (
	       .MPF_DFH_MMIO_ADDR (MPF_DFH_MMIO_ADDR)
	       )
  INST_GEMM_TOP 
    (
`ifdef ENABLE_ASYNC
			      .clk           ( afu_clk ),
`else
			      .clk           ( pClk ) ,
`endif
			      .rst           ( fiu.reset ),

			      .cp2af_sRxPort ( mpf2af_sRxPort ) ,
			      .af2cp_sTxPort ( af2mpf_sTxPort ) 
			      );

endmodule

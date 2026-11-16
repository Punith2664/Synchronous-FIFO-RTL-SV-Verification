// Parameters

parameter DW = 16;
parameter DEPTH = 8;
parameter AW = $clog2(DEPTH);

// Interface 

interface fifo_if (input bit clk);
	logic rstn;
	logic wr_en;
	logic rd_en;
	logic [DW-1:0] din;
	logic [DW-1:0] dout;
	logic full;
	logic empty;

//clocking block driver

clocking drv_cb @(posedge clk);
	default input #1step output #1ns;
	output rstn;
	output wr_en;
	output rd_en;
	output  din;
	input  dout;
	input full;
	input empty;
endclocking 


//clocking block monitor

clocking mon_cb @(posedge clk);
	default input #1step output #1ns;
	input rstn;
	input wr_en;
	input rd_en;
	input  din;
	input  dout;
	input full;
	input empty;
endclocking 

// modport for drvier

modport DRV (clocking drv_cb,input clk);
modport MON (clocking mon_cb,input clk);

endinterface

// transaction

class transaction;
	     bit rstn;
        rand bit wr_en;
        rand bit rd_en;
        rand bit [DW-1:0] din;
             logic [DW-1:0] dout;
             logic  full;
             logic empty;

	constraint valid_c {
		{wr_en, rd_en} != 2'b00;
	}

	constraint full_bias_c {
		wr_en dist {1'b1 := 80, 1'b0 := 20};
		rd_en dist {1'b1 := 70, 1'b0 := 30};
		}

	function void print(input string tag = "");
        $display("Time=%0t | [%s] | rstn=%0b | wr_en=%0b | rd_en=%0b | din=%0d | dout=%0d | full=%0b | empty=%0b",
                 $time, tag, rstn, wr_en, rd_en, din, dout, full, empty);
    endfunction
endclass

// Generator

class generator;
	mailbox #(transaction) drv_mbx;
	event drv_done;
	int count = 20;

	task run();
		repeat(count) begin
			transaction trans = new();	
			if(!trans.randomize()) $error("Randomization failed!");
				trans.rstn = 1'b1;
				drv_mbx.put(trans);
				trans.print("GENERATOR");
				@(drv_done);
			end
	endtask
endclass

// Driver

class driver;
	virtual fifo_if.DRV vif;
	mailbox #(transaction) drv_mbx;
	event drv_done;

	task reset();
		$display("reseting the ports ....");
		vif.drv_cb.rstn <= 1'b0;
		vif.drv_cb.wr_en <= 1'b0;
		vif.drv_cb.rd_en <= 1'b0;
		vif.drv_cb.din <= '0;
		repeat(2) @(vif.drv_cb);
		vif.drv_cb.rstn <= 1'b1;
		@(vif.drv_cb);
		$display("done resetting ...!");
	endtask

	task run();
		forever begin
			transaction trans;
			drv_mbx.get(trans);

			@(vif.drv_cb);
			vif.drv_cb.rstn <= trans.rstn;
			vif.drv_cb.wr_en <= trans.wr_en;
			vif.drv_cb.rd_en <= trans.rd_en;
			vif.drv_cb.din <= trans.din;
			
			trans.print("DRIVER");
			->drv_done;
		end
	endtask
endclass

// Monitor

class monitor;
	virtual fifo_if.MON vif;
	mailbox #(transaction) scb_mbx;
	
	task run();
		forever begin
			transaction trans = new();

			@(vif.mon_cb);
			trans.rstn = vif.mon_cb.rstn;
			trans.wr_en = vif.mon_cb.wr_en;
			trans.rd_en = vif.mon_cb.rd_en;
			trans.din = vif.mon_cb.din;
			trans.dout = vif.mon_cb.dout;
			trans.full = vif.mon_cb.full;
			trans.empty = vif.mon_cb.empty;
			
			trans.print("MONITOR");
			scb_mbx.put(trans);
		end
	endtask
endclass 
		

// Reference model

class ref_model;
    mailbox #(transaction) scb_mbx; // From Monitor
    mailbox #(transaction) act_mbx; // Actual transactions -> to Scoreboard
    mailbox #(transaction) exp_mbx; // Expected transactions -> to Scoreboard

    bit [DW-1:0] mem_q[$];
    bit [DW-1:0] exp_dout;

    function bit is_full();
        return (mem_q.size() == DEPTH);
    endfunction

    function bit is_empty();
        return (mem_q.size() == 0);
    endfunction

    function void do_reset();
        mem_q.delete();
        exp_dout = '0;
    endfunction

    task run();
        transaction in_t, exp_t;
        do_reset();

        forever begin
            scb_mbx.get(in_t);

            
            exp_t       = new();
            exp_t.rstn  = in_t.rstn;
            exp_t.wr_en = in_t.wr_en;
            exp_t.rd_en = in_t.rd_en;
            exp_t.din   = in_t.din;
            
            
            exp_t.dout  = exp_dout;
            exp_t.full  = is_full();
            exp_t.empty = is_empty();
            
            exp_t.print("REF-MODEL");

           
            act_mbx.put(in_t);
            exp_mbx.put(exp_t);

           
            if (!in_t.rstn) begin
                do_reset();
            end else begin
                bit was_full  = is_full();
                bit was_empty = is_empty();
                
              
                if (in_t.rd_en && !was_empty) begin
                    exp_dout = mem_q.pop_front();
                end
                
                if (in_t.wr_en && !was_full) begin
                    mem_q.push_back(in_t.din);
                end
            end
        end
    endtask
endclass


// Scoreboard (Comparator)
class scoreboard;
    mailbox #(transaction) act_mbx; 
    mailbox #(transaction) exp_mbx; 

    int pass_cnt = 0;
    int err_cnt  = 0;

    task run();
        transaction act_t, exp_t;

        forever begin
            
            act_mbx.get(act_t);
            exp_mbx.get(exp_t);

          
            if ((act_t.dout  === exp_t.dout) &&
                (act_t.full  === exp_t.full) &&
                (act_t.empty === exp_t.empty)) begin
                pass_cnt++;
                $display("Time=%0t | [SCB PASS] dout=%0d (exp=%0d) | full=%0b (exp=%0b) | empty=%0b (exp=%0b)",
                         $time, act_t.dout, exp_t.dout, act_t.full, exp_t.full, act_t.empty, exp_t.empty);
            end else begin
                err_cnt++;
                $error("Time=%0t | [SCB FAIL] ACTUAL: {dout=%0d, full=%0b, empty=%0b} != EXPECTED: {dout=%0d, full=%0b, empty=%0b}",
                       $time, act_t.dout, act_t.full, act_t.empty, exp_t.dout, exp_t.full, exp_t.empty);
            end
        end
    endtask
endclass

// Environment

class environment;
	generator gen;
	driver drv;
	monitor mon;
	ref_model rm;
	scoreboard scb;

	virtual fifo_if vif;

	mailbox #(transaction) drv_mbx, scb_mbx, act_mbx, exp_mbx;

	event drv_done;

	function new(virtual fifo_if vif);
		this.vif = vif;

		drv_mbx = new();
		scb_mbx = new();
		act_mbx = new();
		exp_mbx = new();

		gen = new();
		drv = new();
		mon = new();
		rm = new();
		scb = new();

		gen.drv_mbx = drv_mbx;
		gen.drv_done = drv_done;

		drv.vif = vif.DRV;
		drv.drv_mbx = drv_mbx;
		drv.drv_done = drv_done;

		mon.vif = vif.MON;
		mon.scb_mbx = scb_mbx;

		rm.scb_mbx = scb_mbx;
		rm.act_mbx = act_mbx;
		rm.exp_mbx = exp_mbx;

		scb.act_mbx = act_mbx;
		scb.exp_mbx = exp_mbx;
	endfunction

	task pre_test();
		drv.reset();
	endtask

	task test();
		fork
			gen.run();
			drv.run();
			mon.run();
			rm.run();
			scb.run();
		join_any
	endtask

	task post_test();

		wait(gen.drv_done.triggered);

		repeat(2) @(vif.mon_cb);

		$display("==========================================================");
       		$display("                  TESTBENCH SUMMARY                       ");
        	$display("==========================================================");
        	$display(" Total Transactions Generated : %0d", gen.count);
        	$display(" Scoreboard Passed Checks     : %0d", scb.pass_cnt);
        	$display(" Scoreboard Failed Checks     : %0d", scb.err_cnt);
        		if (scb.err_cnt == 0)
            			$display(" RESULT: *** TEST PASSED ***");
        		else
            			$display(" RESULT: *** TEST FAILED ***");
        			$display("==========================================================");
    	endtask

	task run();
		pre_test();
		test();
		post_test();
		$finish;
	endtask
endclass


module tb_fifo;

    bit clk = 0;
    always #5 clk = ~clk;

    fifo_if intf(clk);

    dut #(
        .DW    (DW),
        .AW    (AW),
        .DEPTH (DEPTH)
    ) u_dut (
        .clk   (intf.clk),
        .rstn  (intf.rstn),
        .wr_en (intf.wr_en),
        .rd_en (intf.rd_en),
        .din   (intf.din),
        .dout  (intf.dout),
        .full  (intf.full),
        .empty (intf.empty)
    );

    environment env;

    initial begin
        
        $dumpfile("fifo_tb.vcd");
        $dumpvars(0, tb_fifo);
	
        env = new(intf);
        env.gen.count = 30; 
        env.run();
    end

endmodule

	

		

		
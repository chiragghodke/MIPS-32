// Code your design here
//This is a 32 bit Reduced instruction set architecture processor. The reference for the code has been taken from the Hardware modelling using Verilog course from NPTEL.
//The code implements R-type and I-type of encoding.
/*R-type encoding uses three register opernds i.e., 2 source and 1 destination register.
31     26 25     21 20    16 15     11 10      6 5        0
------------------------------------------------------------
|opcode  |    rs   |    rt  |    rd   |  shamt  |   funct  |
------------------------------------------------------------
opcode---> 6bit like add is 000000
rs----> source register 1
rt----> source register 2
rd-----> destination register
shamt---> shift amount
funct---> opcode extension*/
/* I-type encoding contains 16-bit immediate data field and uses one source and one destination register.
31     26 25     21 20    16 15                            0
------------------------------------------------------------
|opcode  |    rs   |    rt  |    Immediate data            |
------------------------------------------------------------
opcode---> 6bit like LW is 001000.
rs----> source register 1
rt-----> destination register
 Immediate data ---> 16-bit immediate data
*/
module pipeline_processor (
    clk1,clk2
  );
  input clk1,clk2; // Two-phase clock are used as inputs. The clock pulses are given alternatively to different stages so that no overlapping occurs.
/*There are five stages of piplining 
IF: INSTRUCTION FETCH
ID: INSTRUCTION DECODE/ REGISTER FETCH
EX: EXECUTION/EFFECTIVE ADDRESS CALCULATION
MEM: MEMORY ACCESS/ BRANCH COMPLETION
WB: REGISTER WRITE BACK
*/  
 /*
 IF_ID: It denotes the latch between IF and ID stage.
 ID_EX: It denotes the latch stage between ID and EX stages.
 EX_MEM:It denotes the latch between EX and MEM stage.
 MEM_WB: It denotes the latch between MEM and WB stage.
 */
  reg [31:0] PC, IF_ID_IR,IF_ID_NPC, ID_EX_IR, ID_EX_NPC, ID_EX_A, ID_EX_B, ID_EX_Imm, EX_MEM_IR, EX_MEM_ALUOut, EX_MEM_B;
  reg [2:0] ID_EX_type, EX_MEM_type, MEM_WB_type;
  reg EX_MEM_cond;
  reg [31:0] MEM_WB_IR, MEM_WB_ALUOut, MEM_WB_LMD;
  reg [31:0] Reg [0:31]; //Register bank (32 x 32)
  reg [31:0] Mem [0:1023];// memory(1024 x32)

  parameter ADD = 6'b000000, SUB = 6'b000001, AND = 6'b000010, OR = 6'b000011,
            SLT = 6'b000100, MUL = 6'b000101, HLT = 6'b111111, LW = 6'b001000,
            SW = 6'b001001, ADDI = 6'b001010, SUBI = 6'b001011, SLTI = 6'b001100,
            BNEQZ = 6'b001101, BEQZ = 6'b001110;

  parameter RR_ALU = 3'b000, RM_ALU = 3'b001, LOAD = 3'b010, STORE = 3'b011, BRANCH = 3'b100, HALT = 3'b101;

  reg HALTED; // It is set after a HLT instruction executes and reaches WB stage.
  reg TAKEN_BRANCH; // It is set afterthe decision to take a branch is known. It is required to disable the instructions that have already entered the pipeline from making any state changes.

  //IF Stage: The instruction pointed to program counter(PC) is fetched from memory and next value of program counter is computed.
 //For a branch instruction new value of program counter is target address. So program counter is not updated and new value is stored in NPC register.
  /*IR<--- Mem[PC]
  NPC<--- PC+1*/
  always@(posedge clk1)
  begin
    if (HALTED == 0)
    begin
      if(((EX_MEM_IR[31:26]==BEQZ) && (EX_MEM_cond ==1))||((EX_MEM_IR[31:26] == BNEQZ) && (EX_MEM_cond == 0)))
      begin
        IF_ID_IR <= #2 Mem[EX_MEM_ALUOut];
        TAKEN_BRANCH <= #2 1'b1;
        IF_ID_NPC <= #2 EX_MEM_ALUOut +1;
        PC <= #2 EX_MEM_ALUOut + 1;
      end
      else
      begin
        IF_ID_IR <= #2 Mem[PC];
        IF_ID_NPC <= #2 PC +1;
        PC <= #2 PC +1;
      end
    end
  end

  // ID Stage: The instruction already fetched in IR is decoded. Decoding is done in parallel with reading register operands rs and rt.
 /* A<--- Reg[rs];
  B<---Reg[rt];
  Imm<---IR sign extend 16 bit immediate field
  Imm1<--- Ir sign extend 26-bit immediate field
  A, B, Imm, Imm1 are tempoorary registers.
  */
  always@(posedge clk2)
  begin
    if (HALTED == 0)
    begin
      if (IF_ID_IR[25:21] == 5'b00000)
      begin
        ID_EX_A <= 0;
      end
      else
        ID_EX_A <= #2 Reg[IF_ID_IR[25:21]];    //"rs"

      if (IF_ID_IR[20:16] == 5'b00000)
      begin
        ID_EX_B<=0;
      end
      else
        ID_EX_B <= #2 Reg[IF_ID_IR[20:16]];  //"rt"

      ID_EX_NPC <= #2 IF_ID_NPC;
      ID_EX_IR <= #2 IF_ID_IR;
      ID_EX_Imm <= #2 {{16{IF_ID_IR[15]}},{IF_ID_IR[15:0]}};

      case (IF_ID_IR[31:26])
        ADD, SUB, AND, OR, SLT, MUL:
          ID_EX_type <= #2 RR_ALU;
        ADDI, SUBI,SLTI:
          ID_EX_type <= #2 RM_ALU;
        LW:
          ID_EX_type <= #2 LOAD;
        SW:
          ID_EX_type <= #2 STORE;
        BEQZ, BNEQZ:
          ID_EX_type <= #2 BRANCH;
        HLT:
          ID_EX_type <= #2 HALT;
        default:
          ID_EX_type <= #2 HALT;
      endcase
    end
  end

  // EX Stage: The ALU is used to perform calculation. The exact operation depends on instruction decoded. the ALU operates on operands that have been made ready.
  
 /*Memory Reference: ALUOut<-- A +Imm
 Register-register ALU Instruction: ALUOut<--- A func B
 Register-Immediate ALU Instruction: ALUOut <--- A func Imm
 Branch: ALUOut <--- NPC +Imm
         cond<--- (A == 0)*/
  always@(posedge clk1)
  begin
    if(HALTED == 0)
    begin
      EX_MEM_type <= #2 ID_EX_type;
      EX_MEM_IR <= #2 ID_EX_IR;
      TAKEN_BRANCH <= #2 0;

      case (ID_EX_type)
        RR_ALU:
        begin
          case (ID_EX_IR[31:26])
            ADD:
              EX_MEM_ALUOut <= #2 ID_EX_A + ID_EX_B;
            SUB:
              EX_MEM_ALUOut <= #2 ID_EX_A - ID_EX_B;
            AND:
              EX_MEM_ALUOut <= #2 ID_EX_A & ID_EX_B;
            OR:
              EX_MEM_ALUOut <= #2 ID_EX_A | ID_EX_B;
            SLT:
              EX_MEM_ALUOut <= #2 ID_EX_A< ID_EX_B;
            MUL:
              EX_MEM_ALUOut <= #2 ID_EX_A * ID_EX_B;
            default:
              EX_MEM_ALUOut <= #2 32'hxxxxxxxx;
          endcase
        end
        RM_ALU:
        begin
          case(ID_EX_IR[31:26])
            ADDI:
              EX_MEM_ALUOut <= #2 ID_EX_A + ID_EX_Imm;
            SUBI:
              EX_MEM_ALUOut <= #2 ID_EX_A - ID_EX_Imm;
            SLTI:
              EX_MEM_ALUOut <= #2 ID_EX_A<ID_EX_Imm;
            default:
              EX_MEM_ALUOut <= #2 32'hxxxxxxxx;
          endcase
        end
        LOAD, STORE:
        begin
          EX_MEM_ALUOut <= #2 ID_EX_A + ID_EX_Imm;
          EX_MEM_B <= #2 ID_EX_B;
        end
        BRANCH:
        begin
          EX_MEM_ALUOut <= #2 ID_EX_NPC + ID_EX_Imm;
          EX_MEM_cond <= #2 (ID_EX_A == 0);
        end
      endcase
    end
  end

  //MEM STAGE: The only instructions that make use of this step are loads, stores and branches.The load and store instructions access the memory.The branch instruction updates program counter depending upon the outcome of branch condition.
/* Load instruction: PC<---NPC;
                     LMD<---Mem[ALUOut];
   Store Instruction: PC<---NPC;
                      Mem[ALUOut]<---B;
    Branch Instruction: if(cond)PC<--- ALUOut;
                        else PC<--- NPC;
     Other Instruction: PC<--- NPC;*/  
  
  always@(posedge clk2)
  begin
    if(HALTED == 0)
    begin
      MEM_WB_type <= EX_MEM_type;
      MEM_WB_IR <= #2 EX_MEM_IR;

      case(EX_MEM_type)
        RR_ALU, RM_ALU:
          MEM_WB_ALUOut <= #2 EX_MEM_ALUOut;

        LOAD:
          MEM_WB_LMD <= #2 Mem[EX_MEM_ALUOut];
        STORE:
          if (TAKEN_BRANCH == 0) // This is used to disable write. 
          begin
            Mem[EX_MEM_ALUOut] <= #2 EX_MEM_B;
          end
      endcase
    end
  end

  // WB Stage: The results are written back into the register in this step.Results can come from the ALU or the memory system.The position of destination register int he instruction word depends on the instruction.
  
  /*Register-Register ALU Instruction: Reg[rd]<---ALUOut;
  Register-Immediate ALU Instruction: Reg[rt]<---ALUOut;
  Load Instruction: Reg[rt]<---LMD;*/
  always@(posedge clk1)
  begin
    if (TAKEN_BRANCH == 0) // Disable write if branch is taken 
    case (MEM_WB_type)
      RR_ALU:
        Reg[MEM_WB_IR[15:11]] <= #2 MEM_WB_ALUOut; //"rd"
      RM_ALU:
        Reg[MEM_WB_IR[20:16]] <= #2 MEM_WB_ALUOut; // "rt"
      LOAD:
        Reg[MEM_WB_IR[20:16]] <= #2 MEM_WB_LMD; //"rt"
      HALT:
        HALTED<= #2 1'b1;
    endcase
  end
endmodule

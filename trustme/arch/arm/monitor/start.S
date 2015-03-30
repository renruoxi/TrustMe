
#define   TOPPERS_MACRO_ONLY
#include "arm.h"
#include "smc.h"


#define BankedOffset    (N_IRQ_SPSR_CORE0 - NtContextBase)
.macro GetContextBase context
     ldr sp, =\context
.endm


.macro SaveState
        stmdb   sp, {r0-lr}^
        add     r6, sp, #BankedOffset
        cps     #CPSR_MODE_IRQ
        mrs     r12, spsr
        stmia   r6!, {r12-lr}
        cps     #CPSR_MODE_SVC
        mrs     r12, spsr
        stmia   r6!, {r12-lr}
        cps     #CPSR_MODE_ABORT
        mrs     r12, spsr
        stmia   r6!, {r12-lr}
        cps     #CPSR_MODE_UNDEF
        mrs     r12, spsr
        stmia   r6!, {r12-lr}
        cps     #CPSR_MODE_FIQ
        mrs     r7, spsr
        stmia   r6, {r7-lr}
        cps     #CPSR_MODE_MONITOR
.endm

.macro LoadState
        add     r6, sp, #BankedOffset
        cps     #CPSR_MODE_IRQ
        ldmia   r6!, {r12-lr}
        msr     spsr_fsxc, r12
        cps     #CPSR_MODE_SVC
        ldmia   r6!, {r12-lr}
        msr     spsr_fsxc, r12
        cps     #CPSR_MODE_ABORT
        ldmia   r6!, {r12-lr}
        msr     spsr_fsxc, r12
        cps     #CPSR_MODE_UNDEF
        ldmia   r6!, {r12-lr}
        msr     spsr_fsxc, r12
        cps     #CPSR_MODE_FIQ
        ldmia   r6, {r7-lr}
        msr     spsr_fsxc, r7
        cps     #CPSR_MODE_MONITOR
        ldmdb   sp, {r0-lr}^
.endm




	.section .vector, "a"
    .align 5
    .globl monitor_vector_table_base
monitor_vector_table_base:
    ldr pc, reset_vector       
    ldr pc, undef_vector       
    ldr pc, smc_vector         
    ldr pc, prefech_vector     
    ldr pc, data_abort_vector  
    ldr pc, reset_vector      
    ldr pc, irq_vector         
    ldr pc, fiq_vector 
.global  linux_start_info
linux_start_info:
	.long  re_ro
	.long  re_r1
	.long  re_r2
	.long  re_r3

reset_vector:
    .long   _start
undef_vector:
    .long   disaster
smc_vector:
    .long   smc_handler
prefech_vector:
    .long   disaster
data_abort_vector:
    .long   data_abort_handler
irq_vector:
    .long   irq_handler
fiq_vector:
    .long   fiq_handler
disaster: 
    b   disaster
data_abort_handler:
    b data_abort_handler
irq_handler :
    
	set_smm_stack
    stmfd sp!, {r0-r3, ip, lr}
	bl  monitor_irq_handler  
    ldmfd sp!, {r0-r3, ip, lr}
    CP15_SCR_READ sp
    tst sp, #SCR_BIT_0_NS

	bne to_t_irq
    

    GetContextBase TContextBase
    srsia   #CPSR_MODE_MONITOR  // [sp_mon] = lr_mon, [sp_mon, #4] = spsr_mon
    SaveState                   // S-Context = Context

    GetContextBase NtContextBase 

    LoadState                   // Context = N-Context


    mov lr, #SCR_NS             // lr_mon = Normal SCR Config
    CP15_SCR_WRITE lr           // cp15_SCR = lr_mon (N-World Config)

    /* flush the branch target address cache */
    CP15_Flush_BTAC lr          // flush BTAC (corrupts lr_mon)

    /* switch to non-trust world */
	ldr lr,[sp]    	
	subs lr,lr,#4  
	str   lr,[sp]
    rfeia   sp 

to_t_irq:

  
  
   
    /* go to secure world, to save NT state in secure memory */
    mov     sp, #SCR_S          // lr_mon = Secure World SCR config
    CP15_SCR_WRITE  sp          // cp15_SCR = lr_mon (S-World Config)

    /* save NT world state */
    /* sp = NtContextBase */
    GetContextBase NtContextBase 

    srsia #CPSR_MODE_MONITOR
    SaveState                   // N-Context = Context

    /* Load the trust world state */
    /* Note: BTAC flush is automatic in this direction */
    /* sp = TContextBase */
    GetContextBase TContextBase 

    LoadState                   // Context = S-Context
	ldr lr,[sp]    	
	subs lr,lr,#4  
/*	str   lr,[sp]*/
    rfeia   sp                  // switch to the trust-world os

fiq_handler :
	b fiq_handler
	.text    
	.align 5
    .globl _start
_start:
   
    cps #CPSR_MODE_MONITOR
	ldr re_r0, r0
	ldr re_r1, r1
	ldr re_r2, r2
	ldr re_r3, r3
    set_smm_stack 
    mov r0, #SCR_S                 
    CP15_SCR_WRITE r0

  
    ldr   r0, =monitor_init
    cmp   r0, #0x00
    movne lr, pc
    movne pc, r0
	  

	cps #CPSR_MODE_SVC
	ldr  r0,=service_index_base_addr	
	ldr  r1,=index_num	
	ldr  r1,[r1]
	ldr  r2, =secure_os_base    
	mov  pc,r2
l_end:
    b   l_end


	.text
	.align 5
	.globl smc_handler
smc_handler:
	
	CP15_SCR_READ sp
    tst sp, #SCR_BIT_0_NS

	bne nt_smc_handler
    cmp r0, #SMC_SWATCH
    beq t_smc_swich
	
	cmp r0, #T_SMC_BOOT
	beq t_smc_boot

t_smc_handler:
    /* Call syscall function*/
    set_smm_stack
    stmfd sp!, {r0-r3, ip, lr}
    adr   lr, t_smc_handler_exit
	bl  secure_smc_handler   
	
t_smc_handler_exit:
   stmfd sp!,{r0}
   ldmfd sp!, {r0-r3, ip, lr}
   movs  pc, lr
 
t_smc_swich:
   /*first we save the Trust context */
    /* sp <= TContextBase */
    GetContextBase TContextBase
    srsia   #CPSR_MODE_MONITOR  // [sp_mon] = lr_mon, [sp_mon, #4] = spsr_mon
    SaveState                   // S-Context = Context


    /* load the non-trust context state */
    /* sp = NtContextBase */
    GetContextBase NtContextBase 

    LoadState                   // Context = N-Context

    /* set the SCR to non-trust world settings */
    mov lr, #SCR_NS             // lr_mon = Normal SCR Config
    CP15_SCR_WRITE lr           // cp15_SCR = lr_mon (N-World Config)

    /* flush the branch target address cache */
    CP15_Flush_BTAC lr          // flush BTAC (corrupts lr_mon)

t_smc_switch_exit:
    /* switch to non-trust world */
    rfeia   sp 
t_smc_boot:
	 GetContextBase TContextBase
    srsia   #CPSR_MODE_MONITOR  // [sp_mon] = lr_mon, [sp_mon, #4] = spsr_mon
    SaveState 
    
 	mov lr, #SCR_NS             // lr_mon = Normal SCR Config
    CP15_SCR_WRITE lr           // cp15_SCR = lr_mon (N-World Config)

    /* flush the branch target address cache */
    CP15_Flush_BTAC lr          // flush BTAC (corrupts lr_mon)
	ldr lr, =normal_os_base	
	movs  pc, lr


nt_smc_handler: 


    /* switch to NT (and pass arguments) */
    cmp r0, #SMC_SWATCH
    beq nt_smc_switch
    set_smm_stack
    stmfd sp!, {r0-r3, ip, lr}
    adr   lr, nt_smc_handler_exit
	bl  nornal_smc_handler   
	mov r4,r0
nt_smc_handler_exit:
	
	ldmfd sp!, {r0-r3, ip, lr}
	
	mov r0,r4
	movs  pc, lr 	
    b nt_smc_return_to_nt



nt_smc_switch:
    /* go to secure world, to save NT state in secure memory */
    mov     sp, #SCR_S          // lr_mon = Secure World SCR config
    CP15_SCR_WRITE  sp          // cp15_SCR = lr_mon (S-World Config)

    /* save NT world state */
    /* sp = NtContextBase */
    GetContextBase NtContextBase 

    srsia #CPSR_MODE_MONITOR
    SaveState                   // N-Context = Context
nt_smc_switch_exit:
    /* Load the trust world state */
    /* Note: BTAC flush is automatic in this direction */
    /* sp = TContextBase */
    GetContextBase TContextBase 

    LoadState                   // Context = S-Context
    rfeia   sp                  // switch to the trust-world os

nt_smc_return_to_nt:
    movs pc, lr



/*
 * =================
 * Core 0
 * =================
 */
    .bss
    .align 5
    .global NtContextSavedArea
    .global NtContextSavedAreaEnd
    .global TContextSavedArea
    .global TContextSavedAreaEnd
    .global NtContextBase
    .global TContextBase

NtContextSavedArea:
N_USR_R0_CORE0       : .long 0x00
N_USR_R1_CORE0       : .long 0x00
N_USR_R2_CORE0       : .long 0x00
N_USR_R3_CORE0       : .long 0x00
N_USR_R4_CORE0       : .long 0x00
N_USR_R5_CORE0       : .long 0x00
N_USR_R6_CORE0       : .long 0x00
N_USR_R7_CORE0       : .long 0x00
N_USR_R8_CORE0       : .long 0x00
N_USR_R9_CORE0       : .long 0x00
N_USR_R10_CORE0      : .long 0x00
N_USR_R11_CORE0      : .long 0x00
N_USR_R12_CORE0      : .long 0x00
N_USR_SP_CORE0       : .long 0x00
N_USR_LR_CORE0       : .long 0x00

NtContextBase:

N_PC_CORE0           : .long 0x00    // PC to load to return to Normal World
N_CPSR_CORE0         : .long 0x00    // CPSR to load when returning to Normal World
N_SCRATCH_CORE0      : .long 0x00
N_IRQ_SPSR_CORE0     : .long 0x00    // Normal World IRQ mode SPSR, SP and LR reg
N_IRQ_SP_CORE0       : .long 0x00
N_IRQ_LR_CORE0       : .long 0x00
N_SVC_SPSR_CORE0     : .long 0x00    // etc.
N_SVC_SP_CORE0       : .long 0x00
N_SVC_LR_CORE0       : .long 0x00
N_ABT_SPSR_CORE0     : .long 0x00
N_ABT_SP_CORE0       : .long 0x00
N_ABT_LR_CORE0       : .long 0x00
N_UND_SPSR_CORE0     : .long 0x00
N_UND_SP_CORE0       : .long 0x00
N_UND_LR_CORE0       : .long 0x00
N_FIQ_SPSR_CORE0     : .long 0x00
N_FIQ_R8_CORE0       : .long 0x00
N_FIQ_R9_CORE0       : .long 0x00
N_FIQ_R10_CORE0      : .long 0x00
N_FIQ_R11_CORE0      : .long 0x00
N_FIQ_R12_CORE0      : .long 0x00
N_FIQ_SP_CORE0       : .long 0x00
N_FIQ_LR_CORE0       : .long 0x00
NtContextSavedAreaEnd:


TContextSavedArea:

S_USR_R0_CORE0       : .long 0x00    // Secure World USR/SYS registers
S_USR_R1_CORE0       : .long 0x00
S_USR_R2_CORE0       : .long 0x00
S_USR_R3_CORE0       : .long 0x00
S_USR_R4_CORE0       : .long 0x00
S_USR_R5_CORE0       : .long 0x00
S_USR_R6_CORE0       : .long 0x00
S_USR_R7_CORE0       : .long 0x00
S_USR_R8_CORE0       : .long 0x00
S_USR_R9_CORE0       : .long 0x00
S_USR_R10_CORE0      : .long 0x00
S_USR_R11_CORE0      : .long 0x00
S_USR_R12_CORE0      : .long 0x00
S_USR_SP_CORE0       : .long 0x00
S_USR_LR_CORE0       : .long 0x00

TContextBase:

S_PC_CORE0           : .long 0x00    // PC to load to return to Secure World
S_CPSR_CORE0         : .long 0x00    // CPSR to load to return to Secure World
S_SCRATCH_CORE0      : .long 0x00
S_IRQ_SPSR_CORE0     : .long 0x00    // Secure World IRQ mode SPSR, SP and LR reg
S_IRQ_SP_CORE0       : .long 0x00
S_IRQ_LR_CORE0       : .long 0x00
S_SVC_SPSR_CORE0     : .long 0x00    // etc.
S_SVC_SP_CORE0       : .long 0x00
S_SVC_LR_CORE0       : .long 0x00
S_ABT_SPSR_CORE0     : .long 0x00
S_ABT_SP_CORE0       : .long 0x00
S_ABT_LR_CORE0       : .long 0x00
S_UND_SPSR_CORE0     : .long 0x00
S_UND_SP_CORE0       : .long 0x00
S_UND_LR_CORE0       : .long 0x00
S_FIQ_SPSR_CORE0     : .long 0x00
S_FIQ_R8_CORE0       : .long 0x00
S_FIQ_R9_CORE0       : .long 0x00
S_FIQ_R10_CORE0      : .long 0x00
S_FIQ_R11_CORE0      : .long 0x00
S_FIQ_R12_CORE0      : .long 0x00
S_FIQ_SP_CORE0       : .long 0x00
S_FIQ_LR_CORE0       : .long 0x00
TContextSavedAreaEnd:


   

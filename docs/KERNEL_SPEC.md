# SkOS Kernel Specification

**Project:** SkOS  
**Document:** Kernel Specification  
**Status:** Architecture baseline  
**Target architecture:** x86_64 (initial target)  
**Kernel model:** Modular monolithic kernel with strict subsystem boundaries  

---

## 1. Purpose

This document defines the complete baseline architecture of the SkOS kernel. It exists to prevent the kernel from being developed feature-by-feature without a complete architectural contract.

The implementation must follow this order:

1. Specification
2. Public/internal interfaces
3. Implementation
4. Unit/integration tests
5. Hardware/emulator validation
6. Documentation

A subsystem is not considered complete merely because it works in one boot scenario.

---

## 2. Kernel goals

The SkOS kernel must eventually provide:

- CPU and architecture initialization
- Interrupt and exception handling
- Physical and virtual memory management
- Kernel heap and allocators
- Timers and clocks
- Threads and processes
- Preemptive scheduling
- CPU context switching
- User/kernel privilege separation
- System-call ABI
- Inter-process communication
- Handle/file-descriptor infrastructure
- Device model and driver framework
- PCI/ACPI discovery
- Block and character device abstractions
- VFS and filesystem interfaces
- Storage I/O
- Networking interfaces and socket support
- Security and permission primitives
- SMP/multi-core support
- Kernel logging and diagnostics
- Power-management hooks
- Kernel synchronization primitives
- Crash/panic handling
- Kernel testing infrastructure

Not every subsystem must be implemented in the first bootable version. The architecture must reserve a defined place and interface for all of them.

---

## 3. High-level architecture

```text
Firmware (BIOS/UEFI)
        |
        v
   SkOS Bootloader
        |
        | BootInfo
        v
+-----------------------------+
|        Kernel Bootstrap      |
+--------------+--------------+
               |
      +--------+--------+
      | Architecture    |
      | x86_64          |
      +--------+--------+
               |
  +------------+-------------+
  |                          |
  v                          v
Interrupts                 Memory
  |                          |
  +------------+-------------+
               v
        Kernel Core Services
               |
       +-------+-------+
       |               |
       v               v
    Threads         Processes
       |               |
       +-------+-------+
               v
           Scheduler
               |
       +-------+-------+
       |               |
       v               v
      IPC            Syscalls
       |               |
       +-------+-------+
               |
       +-------+--------+----------------+
       |       |        |                |
       v       v        v                v
   Devices   VFS    Networking       Security
       |       |        |                |
       +-------+--------+----------------+
               |
               v
           User Space
               |
       +-------+--------+
       |       |        |
      init   shell    services/apps
```

---

## 4. Kernel design model

SkOS will use a **modular monolithic kernel** initially.

Kernel subsystems run in privileged mode for performance and implementation simplicity, but must communicate through explicit interfaces. The design must avoid a single giant global implementation.

Long-term services that do not require direct privileged execution should be eligible for migration to user space.

### Kernel responsibilities

- CPU control
- Memory protection
- Scheduling
- Interrupt handling
- Core IPC
- Device access
- Filesystem primitives
- Security enforcement
- System-call entry/exit

### User-space responsibilities

- Shell
- Init/session management
- High-level services
- GUI/compositor
- Applications
- Most policy decisions
- High-level networking utilities
- Package management

---

## 5. Source-tree contract

The intended kernel structure is:

```text
kernel/
├── arch/
│   └── x86_64/
│       ├── boot/
│       ├── cpu/
│       ├── gdt/
│       ├── idt/
│       ├── interrupts/
│       ├── apic/
│       ├── timer/
│       ├── paging/
│       ├── context/
│       ├── syscall/
│       └── smp/
│
├── core/
│   ├── kernel.c
│   ├── init.c
│   ├── panic.c
│   ├── log.c
│   ├── error.c
│   └── version.c
│
├── memory/
│   ├── pmm/
│   ├── vmm/
│   ├── heap/
│   ├── slab/
│   └── address_space/
│
├── sync/
│   ├── spinlock/
│   ├── mutex/
│   ├── rwlock/
│   ├── semaphore/
│   ├── waitqueue/
│   └── atomic/
│
├── task/
│   ├── thread/
│   ├── process/
│   ├── scheduler/
│   ├── context/
│   └── signal/
│
├── ipc/
│   ├── pipe/
│   ├── channel/
│   ├── shared_memory/
│   └── event/
│
├── syscall/
│   ├── dispatch.c
│   ├── table.c
│   └── handlers/
│
├── object/
│   ├── object.c
│   ├── handle.c
│   └── fd.c
│
├── device/
│   ├── manager/
│   ├── bus/
│   ├── char/
│   ├── block/
│   └── input/
│
├── drivers/
│   ├── pci/
│   ├── acpi/
│   ├── storage/
│   ├── display/
│   ├── input/
│   ├── network/
│   ├── usb/
│   └── timer/
│
├── storage/
│   ├── block/
│   ├── cache/
│   └── partition/
│
├── vfs/
│   ├── vfs.c
│   ├── vnode.c
│   ├── inode.c
│   ├── dentry.c
│   ├── mount.c
│   └── fd.c
│
├── fs/
│   ├── skfs/
│   ├── fat/
│   └── devfs/
│
├── net/
│   ├── device/
│   ├── ethernet/
│   ├── arp/
│   ├── ipv4/
│   ├── ipv6/
│   ├── icmp/
│   ├── udp/
│   ├── tcp/
│   └── socket/
│
├── security/
│   ├── credentials/
│   ├── permissions/
│   ├── capabilities/
│   └── isolation/
│
├── time/
│   ├── clock.c
│   ├── timer.c
│   └── sleep.c
│
├── power/
│   ├── acpi.c
│   ├── reboot.c
│   └── shutdown.c
│
├── lib/
│   ├── string/
│   ├── memory/
│   ├── bitmap/
│   ├── list/
│   ├── tree/
│   ├── hash/
│   └── printf/
│
└── include/
    └── kernel/
```

The exact filenames may evolve, but the architectural ownership of each subsystem must remain clear.

---

# 6. Architecture layer

The architecture layer is the only part allowed to directly depend on x86_64-specific CPU details.

## 6.1 CPU initialization

Responsibilities:

- Detect CPU features
- Establish required execution mode
- Configure control registers
- Configure model-specific registers where needed
- Detect APIC support
- Detect paging features
- Detect SIMD/FPU capabilities
- Record CPU topology

Required conceptual API:

```c
arch_cpu_init();
arch_cpu_features();
arch_cpu_id();
arch_cpu_halt();
arch_enable_interrupts();
arch_disable_interrupts();
arch_save_flags();
arch_restore_flags();
```

---

## 6.2 GDT

The x86_64 GDT must be defined explicitly.

Required entries may include:

- Kernel code
- Kernel data
- User code
- User data
- TSS

The GDT implementation must not be scattered through unrelated kernel code.

---

## 6.3 IDT

The IDT must support:

- CPU exceptions
- Hardware IRQs
- System-call entry mechanism
- Per-vector dispatch

Every exception must have a defined kernel policy.

Important exceptions include:

- Divide error
- Debug
- Breakpoint
- Invalid opcode
- General protection fault
- Page fault
- Double fault
- Invalid TSS
- Segment-related faults
- Stack fault
- Machine check

---

## 6.4 TSS and privilege transition

TSS must support:

- Ring 3 -> Ring 0 stack transition
- Interrupt stack table where required
- Per-CPU kernel stack configuration

The kernel must never rely on an accidental stack layout.

---

## 6.5 APIC

The architecture must support a modern interrupt controller design.

Initial target:

- Local APIC
- I/O APIC where required
- Interrupt routing
- Per-CPU timer interrupt

Legacy PIC support may be retained only during early bootstrap or compatibility initialization.

---

## 6.6 SMP

Multi-core support is part of the architecture even if disabled initially.

Required concepts:

- CPU discovery
- Bootstrap processor
- Application processors
- Per-CPU data
- Per-CPU scheduler state
- Inter-processor interrupts
- CPU startup/shutdown
- CPU affinity

---

# 7. Interrupt subsystem

The interrupt subsystem provides a common dispatch path:

```text
CPU
 |
 v
Interrupt entry
 |
 v
Register/context capture
 |
 v
Vector classification
 |
 +---- exception
 +---- hardware IRQ
 +---- software/kernel entry
 |
 v
Subsystem handler
 |
 v
Scheduler decision
 |
 v
Return to interrupted context
```

Rules:

- Interrupt handlers must be short.
- Blocking operations are forbidden in interrupt context.
- Allocation must be avoided unless explicitly designed for interrupt context.
- Deferred work must be used for expensive operations.

---

# 8. Time subsystem

The time subsystem is separate from the scheduler.

It provides:

- Monotonic clock
- Wall-clock time
- High-resolution time source where available
- Kernel timers
- Sleep/wakeup infrastructure
- Timer queues

Initial hardware options may include:

- APIC timer
- HPET
- TSC as a clock source when safely calibrated

Timer API concepts:

```c
ktime_now();
timer_create();
timer_start();
timer_cancel();
schedule_timeout();
```

---

# 9. Physical Memory Manager (PMM)

The PMM owns physical RAM allocation.

Input:

- Bootloader memory map

Must classify regions as:

- Usable RAM
- Reserved
- Firmware/ACPI
- Kernel image
- Bootloader data
- MMIO/reserved regions

Initial allocator may use a bitmap.

Required conceptual operations:

```c
phys_alloc_page();
phys_free_page();
phys_alloc_pages(count);
phys_free_pages(address, count);
phys_is_usable(address);
```

The PMM must never return a reserved physical page.

---

# 10. Virtual Memory Manager (VMM)

The VMM owns virtual address spaces and page tables.

Responsibilities:

- Page-table creation
- Mapping/unmapping
- Permissions
- User/kernel separation
- Page-fault support
- Address-space cloning/creation
- TLB management
- Shared mappings
- Memory-mapped I/O

Required page permissions:

- Read
- Write
- Execute
- User
- Global where appropriate

The kernel address space must be deliberately defined rather than relying on arbitrary identity mappings forever.

Conceptual API:

```c
vmm_create_address_space();
vmm_destroy_address_space();
vmm_map();
vmm_unmap();
vmm_protect();
vmm_translate();
```

---

# 11. Kernel heap

The kernel requires dynamic allocation independent of physical page allocation.

Layers:

```text
PMM
  |
VMM
  |
Page allocator
  |
Slab/size allocator
  |
kmalloc/kfree
```

Requirements:

- Alignment
- Double-free detection in debug builds
- Optional guard pages for debug builds
- Allocation statistics
- Clear ownership rules

---

# 12. Synchronization subsystem

Required primitives:

- Atomic operations
- Spinlocks
- Mutexes
- Reader/writer locks
- Semaphores
- Wait queues
- Completion/event primitives

Rules:

- Spinlocks are for short critical sections.
- Mutexes may sleep.
- Interrupt context cannot acquire a sleeping lock.
- Lock ordering must be documented to prevent deadlocks.

---

# 13. Thread subsystem

A thread represents schedulable execution.

Thread structure must conceptually contain:

```text
Thread ID
State
CPU context
Kernel stack
User stack reference
Address-space reference
Scheduling priority
CPU affinity
Time accounting
Wait state
Credentials reference
Open-handle context
```

States:

```text
NEW
READY
RUNNING
BLOCKED
SLEEPING
STOPPED
TERMINATED
```

---

# 14. Context switching

The context-switch subsystem must preserve all architectural state required to resume a thread correctly.

Conceptually:

```text
save current CPU context
 |
update current thread
 |
select next thread
 |
load next CPU context
 |
restore address space if required
 |
return to execution
```

FPU/SIMD state must have an explicit ownership/lazy-save strategy.

---

# 15. Scheduler

Initial scheduler:

- Preemptive
- Round-robin
- Priority-aware extension point
- Per-CPU run queue design compatible with SMP
- Idle thread per CPU

Scheduler responsibilities:

- Choose runnable thread
- Account CPU time
- Handle blocking/wakeup
- Handle timer-driven preemption
- Support CPU affinity later

The scheduler must not know filesystem or device implementation details.

---

# 16. Process subsystem

A process owns an address space and process-level resources.

Conceptual process object:

```text
PID
Parent PID/reference
Address space
Thread list
Credentials
Handle table
Working directory
Environment reference
Resource limits
Process state
Exit status
```

Required lifecycle:

```text
create -> initialize -> runnable -> running -> exit -> reap
```

---

# 17. User/kernel privilege boundary

Kernel code runs in Ring 0.

Applications run in Ring 3.

User memory must not be able to directly access kernel memory.

Every kernel entry from user mode must validate:

- User pointers
- Buffer lengths
- Handles
- IDs
- Enum values
- Permissions
- Object lifetime

Never trust user-space input.

---

# 18. System-call subsystem

System calls are the stable user/kernel API boundary.

The ABI must define:

- System-call numbers
- Argument registers/stack convention
- Return-value convention
- Error convention
- 64-bit ABI rules
- Pointer validation rules
- Restart behavior where applicable

Initial syscall groups:

### Process

```text
process_exit
process_spawn
process_exec
process_wait
process_getpid
```

### Thread

```text
thread_create
thread_exit
thread_sleep
thread_yield
```

### Memory

```text
vm_map
vm_unmap
vm_protect
```

### Files

```text
open
close
read
write
seek
stat
```

### IPC

```text
pipe
channel_create
shared_memory_create
```

### Time

```text
clock_gettime
sleep
```

The actual numeric syscall ABI must be frozen only after the initial interface review.

---

# 19. Kernel object and handle system

Kernel resources should use opaque handles rather than exposing internal pointers to user space.

Examples:

```text
Process handle
Thread handle
File handle
Pipe handle
Socket handle
Event handle
Shared-memory handle
Device handle
```

Each handle must have:

- Type
- Owner/reference
- Permissions
- Lifetime/reference count

This becomes the foundation for safe resource management.

---

# 20. IPC subsystem

Initial IPC mechanisms:

1. Pipes
2. Message channels
3. Shared memory
4. Events/notifications

IPC must define:

- Blocking semantics
- Non-blocking mode
- Buffer limits
- Ownership
- Process termination behavior
- Synchronization

---

# 21. Device model

All drivers must register devices through a common device model.

```text
Bus
 |
 +-- Device
      |
      +-- Driver
           |
           +-- Operations
```

Device classes:

- Character
- Block
- Input
- Display
- Network
- Bus

The device manager owns discovery and registration, not individual applications.

---

# 22. PCI subsystem

PCI must provide:

- Bus enumeration
- Device/function discovery
- Vendor/device IDs
- BAR discovery
- IRQ information
- Capability discovery
- Driver matching
- MMIO/I/O resource registration

Driver matching must be data-driven where possible.

---

# 23. ACPI subsystem

ACPI support must eventually provide:

- RSDP discovery
- RSDT/XSDT parsing
- MADT CPU/APIC information
- HPET discovery
- Power/shutdown information
- Basic device/resource information

ACPI parsing should be isolated from generic device code.

---

# 24. Driver framework

Driver lifecycle:

```text
register
 |
match
 |
probe
 |
initialize
 |
active
 |
remove/shutdown
```

Drivers must not directly depend on unrelated drivers when a generic subsystem interface exists.

Initial drivers:

1. Serial console
2. Framebuffer/display
3. Keyboard
4. Timer
5. PCI
6. Storage

Later:

- Mouse
- USB
- Network
- Audio
- GPU acceleration

---

# 25. Console and logging

Before a full GUI exists, kernel diagnostics must work through a serial or framebuffer console.

Required logging levels:

```text
TRACE
DEBUG
INFO
WARN
ERROR
PANIC
```

Log records should include:

- CPU ID
- Timestamp when available
- Subsystem
- Severity
- Message

Example concept:

```c
klog_info("memory", "PMM initialized: %llu pages", pages);
```

---

# 26. Panic and fault handling

Kernel panic must be deterministic and diagnostic.

On fatal failure, report:

- Exception/vector
- Error code
- CPU/register state
- Instruction pointer
- Stack information where safe
- Current thread/process
- Fault address for page faults
- Kernel version/build identifier

The panic path must not depend on complex services that may already be broken.

---

# 27. VFS

The VFS is the common filesystem interface.

Core concepts:

```text
Mount
Superblock
Inode
Dentry
File
Directory
Path
File descriptor/handle
```

Path resolution:

```text
userspace path
 |
 VFS
 |
 mount lookup
 |
 dentry/path traversal
 |
 inode
 |
 filesystem implementation
 |
 block device
```

---

# 28. Filesystem layer

SkOS should have its own filesystem, tentatively named **SKFS**.

SKFS design must be specified separately before implementation.

Required capabilities for the first practical version:

- Superblock
- Inode table
- Directories
- Regular files
- File metadata
- Allocation map
- Free-space tracking
- Journaling or a clearly documented recovery strategy
- Mount/unmount
- Consistency checking

FAT support may be implemented as a secondary filesystem for interoperability.

---

# 29. Block layer

Storage stack:

```text
Application
 |
Syscall
 |
VFS
 |
Filesystem
 |
Block layer
 |
Storage driver
 |
Controller
 |
Disk/SSD
```

Block layer responsibilities:

- Block requests
- Queuing
- Completion
- Error reporting
- Cache integration
- Device geometry

---

# 30. Page cache / buffer cache

A filesystem should not perform raw device access for every small read.

The storage subsystem should eventually provide:

- Page cache
- Metadata cache
- Buffer cache where needed
- Write-back policy
- Flush/sync operations

Cache coherency rules must be defined before filesystem optimization.

---

# 31. Networking subsystem

Networking is a later milestone but its architecture must be reserved now.

Stack:

```text
Network application
 |
Socket API
 |
TCP/UDP
 |
IPv4/IPv6
 |
ARP/ND
 |
Ethernet
 |
NIC driver
```

Initial requirements:

- Network interface abstraction
- Ethernet frames
- IPv4
- ARP
- ICMP
- UDP
- TCP
- Sockets

IPv6 should be designed as a first-class extension rather than an incompatible rewrite.

---

# 32. Security model

Security must be built into the resource model rather than added after applications exist.

Required foundations:

- User/kernel separation
- Process isolation
- Credentials
- File permissions
- Resource ownership
- Capability/handle validation
- Memory permissions
- Executable/write separation where supported

Future security features may include:

- Capability-based privileges
- Sandboxing
- Secure boot integration
- Signed packages
- Address-space randomization

---

# 33. Time and process sleep

A process/thread must never busy-loop when it needs to wait.

Correct pattern:

```text
request wait
 |
block thread
 |
remove from run queue
 |
timer/event occurs
 |
wake thread
 |
insert into run queue
```

This depends on the scheduler, timer, and wait-queue subsystems working together.

---

# 34. Power management

Required eventual operations:

```text
reboot()
shutdown()
```

Later:

- ACPI power states
- Suspend
- CPU idle states
- Thermal information
- Battery information

---

# 35. Kernel library

Because the kernel cannot depend on a normal user-space libc, it needs a minimal freestanding library.

Required utilities:

- memcpy
- memmove
- memset
- memcmp
- strlen
- strcmp
- string helpers
- integer conversion
- bitmap operations
- intrusive lists
- trees
- hash tables
- formatting/logging helpers

The kernel library must remain freestanding and architecture-independent wherever possible.

---

# 36. Boot information contract

The bootloader must provide a versioned structure to the kernel.

Conceptual structure:

```text
BootInfo
├── magic
├── version
├── kernel image info
├── memory map
├── framebuffer info
├── firmware/ACPI info
├── boot device info
├── CPU/firmware hints
└── command line/options
```

The kernel must validate the magic number and version before consuming the structure.

---

# 37. Kernel initialization order

The canonical initialization order is:

```text
1. CPU early setup
2. Early serial/console
3. BootInfo validation
4. GDT/TSS
5. IDT and exception handlers
6. Interrupt controller
7. Physical memory manager
8. Early virtual memory
9. Kernel heap
10. Time source/timer
11. Synchronization primitives
12. Scheduler infrastructure
13. Thread subsystem
14. Process/address-space subsystem
15. Object/handle subsystem
16. Syscall infrastructure
17. PCI/ACPI/device discovery
18. Storage/block layer
19. VFS
20. Root filesystem
21. User-space loader
22. Init process
23. Remaining services/drivers
```

This ordering is a dependency order, not a requirement that every feature be production-complete before the next milestone.

---

# 38. User-space executable loading

The kernel must eventually provide an executable loader.

Initial loader responsibilities:

- Validate executable format
- Validate architecture
- Create address space
- Map executable segments
- Apply memory permissions
- Create user stack
- Build process arguments/environment
- Set initial instruction pointer
- Enter Ring 3

The executable format must be specified separately. ELF may be used during development, while a native SkOS format can be considered later.

---

# 39. User-space init

The first user process is `init`.

Conceptually:

```text
Kernel
 |
create init
 |
init
 +-- device/service startup
 +-- filesystem setup
 +-- logging/service setup
 +-- terminal/session startup
 +-- shell
```

The kernel should not contain the shell.

---

# 40. Error handling

Every kernel subsystem must use defined error codes.

Errors must distinguish at least:

- Invalid argument
- Permission denied
- Not found
- Busy
- Out of memory
- Already exists
- Not supported
- Timeout
- Interrupted
- I/O error
- Invalid handle
- Fault

Internal kernel errors and user-visible syscall errors should be mapped deliberately.

---

# 41. Reference counting and lifetime

Objects that can be referenced by multiple kernel subsystems need explicit lifetime rules.

Example:

```text
Process
  |
  +-- Thread references
  +-- Handle references
  +-- Address-space reference
  +-- Parent/child references
```

No subsystem may free an object while another subsystem can still legally reference it.

---

# 42. Interrupt vs process context rules

Every kernel function must have a documented execution-context requirement where relevant.

Possible contexts:

```text
BOOTSTRAP
PROCESS
THREAD
INTERRUPT
NMI
PANIC
```

For each API, document whether it:

- May sleep
- May allocate
- May take a mutex
- May be called from interrupt context

This rule is mandatory for avoiding subtle kernel deadlocks and crashes.

---

# 43. Testing strategy

Testing must exist at four levels.

## Level 1: Host-side tests

Test architecture-independent data structures and algorithms outside the kernel.

Examples:

- Bitmap allocator logic
- Linked lists
- Trees
- Hash tables
- Path parsing
- Filesystem metadata algorithms

## Level 2: Kernel unit tests

Run inside a test kernel where practical.

## Level 3: Emulator/integration tests

Primary development target should be QEMU.

Tests include:

- Boot
- Exceptions
- Memory allocation
- Paging
- Context switching
- Syscalls
- Process creation
- Filesystem mounting
- Device discovery

## Level 4: Real hardware validation

Real hardware is a later validation stage, not the primary debugging environment.

---

# 44. Debugging requirements

Development must support:

- Serial logs
- QEMU debug output
- Symbolized kernel addresses
- Debug builds
- Assertions
- Stack traces
- Kernel panic dump
- Optional GDB remote debugging

Every major subsystem should have a minimal self-test or diagnostic command.

---

# 45. Build requirements

The kernel must be built as a freestanding target.

The build system must clearly separate:

```text
bootloader
kernel
userspace
libraries
host tools
filesystem image generation
```

A reproducible cross-compilation environment is preferred.

No accidental dependency on the host operating system's libc or runtime is allowed in kernel code.

---

# 46. Architecture-independent vs architecture-dependent code

Architecture-independent code belongs outside `arch/`.

Bad:

```text
scheduler/x86_specific_code.c
```

Preferred:

```text
scheduler/scheduler.c
arch/x86_64/context_switch.S
```

The generic scheduler calls an architecture interface for context switching.

---

# 47. Public kernel interfaces

Subsystem interfaces should be narrow.

Examples:

```text
arch -> generic kernel
pmm  -> vmm
vmm  -> process
scheduler -> thread
thread -> process
vfs -> filesystem
filesystem -> block layer
driver -> device manager
syscall -> kernel subsystems
```

Circular dependencies must be avoided.

---

# 48. Dependency rules

The following rules are mandatory:

1. Architecture code may implement architecture interfaces but generic code must not include random architecture internals.
2. Drivers use device interfaces rather than reaching into unrelated driver internals.
3. Filesystems use VFS/block interfaces.
4. User applications use syscalls or user-space libraries.
5. Kernel subsystems must not call user-space code synchronously.
6. Interrupt handlers must not block.
7. Memory management must be usable before most higher-level subsystems start.
8. Scheduler and synchronization primitives must have clearly defined initialization phases.
9. No subsystem may silently depend on another subsystem being initialized earlier than its documented dependency.
10. Every resource must have an ownership/lifetime rule.

---

# 49. Initial implementation milestones

## M0 — Architecture

Deliver:

- This specification
- Repository structure
- Build plan
- BootInfo definition
- Coding rules

## M1 — Boot

Deliver:

- Bootloader
- Kernel entry
- BootInfo handoff
- Serial output

## M2 — CPU and interrupts

Deliver:

- GDT
- IDT
- Exceptions
- TSS
- Interrupt controller

## M3 — Physical memory

Deliver:

- Memory map parser
- PMM
- Page allocation/free

## M4 — Virtual memory

Deliver:

- Page tables
- Kernel virtual address space
- Mapping/unmapping
- Page faults

## M5 — Kernel heap

Deliver:

- kmalloc/kfree
- Allocation diagnostics

## M6 — Timer and synchronization

Deliver:

- Timer
- Clock
- Spinlock
- Mutex
- Wait queue

## M7 — Threads and scheduler

Deliver:

- Thread creation
- Context switch
- Round-robin scheduling
- Preemption

## M8 — Processes and user mode

Deliver:

- Process object
- Address-space ownership
- Ring 3 entry
- First user program

## M9 — Syscalls

Deliver:

- Syscall entry
- Dispatcher
- Initial syscall ABI

## M10 — Handles and IPC

Deliver:

- Handle table
- Pipes
- Channels
- Shared memory

## M11 — Devices

Deliver:

- Device manager
- PCI
- Keyboard
- Display/framebuffer
- Storage

## M12 — VFS/storage

Deliver:

- VFS
- Block layer
- Initial SKFS
- File syscalls

## M13 — Init and shell

Deliver:

- init
- terminal
- shell
- process launching

## M14 — Networking

Deliver:

- NIC abstraction
- Ethernet
- IPv4
- UDP/TCP
- sockets

## M15 — SMP and hardening

Deliver:

- Multi-core boot
- Per-CPU data
- SMP scheduler
- Stronger isolation
- Resource limits

## M16 — GUI

Deliver:

- Graphics service
- Compositor
- Window manager
- GUI toolkit

---

# 50. Definition of a real boot milestone

A milestone is successful only when it can be reproduced from a clean build.

For example, the first user-mode milestone should be:

```text
Power on
  -> Firmware
  -> SkOS Bootloader
  -> Kernel
  -> Memory initialization
  -> Interrupts
  -> Scheduler
  -> User address space
  -> Ring 3
  -> init
  -> user program
```

The kernel must not rely on hidden initialization performed by the emulator or debugger.

---

# 51. First version scope

The first usable SkOS kernel should NOT attempt to implement everything in this document.

The first target is:

```text
Boot
 |
CPU
 |
Interrupts
 |
Memory
 |
Timer
 |
Threads
 |
Scheduler
 |
Processes
 |
User mode
 |
Syscalls
 |
Init
 |
Shell
```

Storage, networking, GUI, SMP, and advanced security follow after the core execution environment is stable.

---

# 52. Non-negotiable architectural decisions

1. **SkOS is the operating-system name.**
2. **Initial CPU target is x86_64.**
3. **The kernel is written as a freestanding kernel.**
4. **Bootloader and kernel have a versioned BootInfo contract.**
5. **User space is separated from kernel space.**
6. **The shell is user space.**
7. **GUI is not kernel code.**
8. **Filesystem is separated from storage drivers through VFS/block layers.**
9. **Scheduler is separated from timer hardware.**
10. **Generic kernel code must not depend directly on x86_64 internals.**
11. **Every subsystem has an explicit interface and ownership model.**
12. **QEMU is the primary development/test environment.**
13. **The architecture is defined before implementation of large subsystems.**
14. **Breaking an interface requires updating this specification and dependent code deliberately.**

---

# 53. Completion checklist

## Architecture

- [ ] x86_64 architecture layer
- [ ] GDT
- [ ] IDT
- [ ] TSS
- [ ] APIC
- [ ] SMP
- [ ] Context switching

## Interrupts/time

- [ ] Exceptions
- [ ] IRQ dispatch
- [ ] Timer
- [ ] Monotonic clock
- [ ] Sleep/wakeup

## Memory

- [ ] Boot memory map
- [ ] PMM
- [ ] VMM
- [ ] Kernel heap
- [ ] Slab/allocator strategy
- [ ] Address-space management
- [ ] Page-fault handling

## Tasks

- [ ] Threads
- [ ] Processes
- [ ] Scheduler
- [ ] Preemption
- [ ] CPU affinity
- [ ] Process lifecycle

## Protection

- [ ] Ring 3
- [ ] User/kernel memory separation
- [ ] Handle validation
- [ ] Credentials
- [ ] Permissions

## Syscalls/IPC

- [ ] Syscall ABI
- [ ] Dispatcher
- [ ] Handle table
- [ ] Pipes
- [ ] Channels
- [ ] Shared memory
- [ ] Events

## Devices

- [ ] Device model
- [ ] PCI
- [ ] ACPI
- [ ] Keyboard
- [ ] Display
- [ ] Storage
- [ ] Network
- [ ] USB

## Storage

- [ ] Block layer
- [ ] VFS
- [ ] SKFS
- [ ] FAT interoperability
- [ ] Cache
- [ ] Mount/unmount

## Networking

- [ ] Ethernet
- [ ] ARP
- [ ] IPv4
- [ ] IPv6
- [ ] ICMP
- [ ] UDP
- [ ] TCP
- [ ] Sockets

## User space

- [ ] Executable loader
- [ ] init
- [ ] libc-equivalent base library
- [ ] shell
- [ ] services
- [ ] applications

## Reliability

- [ ] Logging
- [ ] Assertions
- [ ] Panic handler
- [ ] Stack traces
- [ ] Host tests
- [ ] Kernel tests
- [ ] QEMU integration tests
- [ ] Reproducible builds

---

# 54. Development rule for SkOS

When a new feature is requested, first answer these questions before writing code:

1. Which subsystem owns it?
2. Is it kernel-space or user-space?
3. What interface does it use?
4. What does it depend on?
5. What depends on it?
6. What are its memory/lifetime rules?
7. Can it execute in interrupt context?
8. How is it tested?
9. What happens on failure?
10. Does the architecture document need an update?

If these questions cannot be answered, implementation should stop until the design is clarified.

---

## Final architectural principle

**SkOS must be developed as a system, not as a collection of features.**

The kernel is the foundation. Bootloader, memory, interrupts, scheduling, processes, system calls, drivers, storage, networking, security, and user space must have defined boundaries and dependencies before implementation expands.

This document is the baseline contract for the new SkOS kernel and should be updated whenever a deliberate architectural decision changes.

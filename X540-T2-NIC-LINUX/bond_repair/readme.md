```
$ lspci -v | grep -A 10 -i ethernet
03:00.0 Ethernet controller: Intel Corporation Ethernet Controller 10-Gigabit X540-AT2 (rev 01)
	Subsystem: Inspur Electronic Information Industry Co., Ltd. 10G base-T DP EP102Ti3A Adapter
	Flags: bus master, fast devsel, latency 0, IRQ 39, IOMMU group 22
	Memory at 7c22400000 (64-bit, prefetchable) [size=2M]
	Memory at 7c22a04000 (64-bit, prefetchable) [size=16K]
	Capabilities: <access denied>
	Kernel driver in use: ixgbe
	Kernel modules: ixgbe

03:00.1 Ethernet controller: Intel Corporation Ethernet Controller 10-Gigabit X540-AT2 (rev 01)
	Subsystem: Inspur Electronic Information Industry Co., Ltd. 10G base-T DP EP102Ti3A Adapter
	Flags: bus master, fast devsel, latency 0, IRQ 41, IOMMU group 23
	Memory at 7c22200000 (64-bit, prefetchable) [size=2M]
	Memory at 7c22a00000 (64-bit, prefetchable) [size=16K]
	Capabilities: <access denied>
	Kernel driver in use: ixgbe
	Kernel modules: ixgbe

--
09:00.0 Ethernet controller: Intel Corporation I211 Gigabit Network Connection (rev 03)
	Subsystem: ASRock Incorporation I211 Gigabit Network Connection
	Flags: bus master, fast devsel, latency 0, IRQ 24, IOMMU group 27
	Memory at fc600000 (32-bit, non-prefetchable) [size=128K]
	I/O ports at f000 [disabled] [size=32]
	Memory at fc620000 (32-bit, non-prefetchable) [size=16K]
	Capabilities: <access denied>
	Kernel driver in use: igb
	Kernel modules: igb

0b:00.0 Non-Essential Instrumentation [1300]: Advanced Micro Devices, Inc. [AMD] Starship/Matisse Reserved SPP
```

```mermaid
flowchart TD
    Start([Start Multi-NIC Beast Mode]) --> Setup[Setup Beast Mode]
    
    Setup --> Detect[Detect Network Interfaces]
    Detect --> Select[User Selects Interfaces]
    Select --> Config[Configure Selected Interfaces]
    
    Config --> IncreaseFD[Increase File Descriptor Limit]
    IncreaseFD --> OptimizeNet[Optimize Network Settings]
    
    OptimizeNet --> GetInput[Get User Input<br/>URL & Target Directory]
    GetInput --> Validate[Validate URL]
    
    Validate --> CreateDir[Create Target Directory]
    CreateDir --> InitLogs[Initialize Log Files]
    
    InitLogs --> InitSystem[Initialize Multi-NIC System]
    InitSystem --> InitRateLimit[Initialize Rate Limiting]
    
    InitRateLimit --> StartWorkers[Start Multi-NIC Workers]
    StartWorkers --> StartMonitors[Start Monitoring Services]
    
    StartMonitors --> CreateCollector[Create Beast Collector]
    CreateCollector --> SetupCallbacks[Setup Crawling Callbacks]
    
    SetupCallbacks --> StartCrawl[Start Crawling]
    
    StartCrawl --> Wait[Wait for Completion]
    
    Wait --> Shutdown[Shutdown Sequence]
    Shutdown --> FinalStats[Print Final Stats]
    FinalStats --> End([End])
    
    %% Monitoring Services
    StartMonitors --> Scalers[Start 16 Scalers]
    StartMonitors --> PerfMon[Performance Monitor]
    StartMonitors --> MemMon[Memory Monitor]
    StartMonitors --> NetMon[Network Monitor]
    
    %% Multi-NIC System Initialization
    subgraph InitSystem [Initialize Multi-NIC System]
        direction LR
        InitQ[Create Queues per Interface]
        InitClients[Create HTTP Clients per Interface]
    end
    
    %% Worker System
    subgraph StartWorkers [Start Multi-NIC Workers]
        direction LR
        ForEachInterface[For Each Interface]
        ForEachInterface --> StartInterfaceWorkers[Start Workers per Interface]
    end
    
    %% Crawling Process
    subgraph SetupCallbacks [Setup Crawling Callbacks]
        direction TB
        OnRequest[OnRequest: First Visit]
        OnResponse[OnResponse: Logging]
        OnError[OnError: Error Handling]
        OnHTMLLinks[OnHTML: Link Discovery]
        OnHTMLDocs[OnHTML: Document Detection]
    end
    
    %% Document Processing
    OnHTMLDocs --> CheckDoc[Check if Document URL]
    CheckDoc --> CheckPending[Check if Already Downloaded/Pending]
    CheckPending --> SelectInterface[Select Interface Load Balancing]
    SelectInterface --> CreateTask[Create Download Task]
    
    CreateTask --> TryEnqueue{Try to Enqueue}
    TryEnqueue -->|Interface Queue| InterfaceQueue[Add to Interface Queue]
    TryEnqueue -->|Priority Queue| PriorityQueue[Add to Priority Queue]
    TryEnqueue -->|Both Full| ForceScale[Force Scale Up]
    ForceScale --> Persistent[Persistent Enqueue Attempt]
    
    %% Worker Processing
    subgraph WorkerProcess [Worker Processing Loop]
        direction LR
        GetTask[Get Task from Queue]
        RateLimit[Apply Rate Limiting]
        Download[Download Document]
        CheckSuccess{Download Success?}
        
        CheckSuccess -->|Yes| MarkSuccess[Mark Completed]
        CheckSuccess -->|No| CheckRetries{Retries Left?}
        
        CheckRetries -->|Yes| Retry[Requeue with Priority]
        CheckRetries -->|No| MarkFailed[Mark Failed]
    end
    
    InterfaceQueue --> WorkerProcess
    PriorityQueue --> WorkerProcess
    
    %% Scaling System
    subgraph Scaling [Dynamic Scaling System]
        direction TB
        MonitorQueues[Monitor Queue Utilization]
        CheckThreshold{Utilization > Threshold?}
        CheckWorkers{Workers < Max?}
        
        CheckThreshold -->|Yes| CheckWorkers
        CheckWorkers -->|Yes| ScaleUp[Scale Up Workers]
        CheckWorkers -->|No| WaitNextCheck[Wait Next Check]
    end
    
    %% Style Definitions
    classDef process fill:#e1f5fe,stroke:#01579b
    classDef decision fill:#fff3e0,stroke:#ef6c00
    classDef queue fill:#f3e5f5,stroke:#7b1fa2
    classDef monitor fill:#e8f5e8,stroke:#2e7d32
    
    class Start,End,Setup,Detect,Select,Config,IncreaseFD,OptimizeNet,GetInput,Validate,CreateDir,InitLogs,InitSystem,InitRateLimit,StartWorkers,CreateCollector,SetupCallbacks,StartCrawl,Wait,Shutdown,FinalStats process
    class CheckDoc,CheckPending,CheckSuccess,CheckRetries,CheckThreshold,CheckWorkers decision
    class InterfaceQueue,PriorityQueue queue
    class Scalers,PerfMon,MemMon,NetMon,MonitorQueues monitor
```

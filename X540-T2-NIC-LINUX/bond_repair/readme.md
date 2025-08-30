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

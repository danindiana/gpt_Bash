This Bash script, `set_irq_affinity`, is designed to affinitize network interface interrupts to specific CPU cores. This can be useful for optimizing network performance by ensuring that interrupts from network interfaces are handled by specific CPU cores, reducing context switches and improving cache locality.

### Key Features:
1. **Interrupt Affinity**: The script sets the `smp_affinity` for each interrupt associated with the specified network interfaces.
2. **XPS (Transmit Packet Steering)**: The script can optionally configure XPS, which allows the kernel to steer packets to specific CPU cores for transmission.
3. **Node-based Affinity**: The script supports affinity based on local or remote NUMA nodes.
4. **Custom Core Assignment**: The script allows for custom core assignments via user input.

### Usage:
The script supports several command-line options and modes:
- **Show Current Settings**: `-s` option to display the current affinity settings.
- **Configure XPS**: `-x` option to enable XPS.
- **Disable XPS**: `-X` option to disable XPS.
- **Affinity Modes**:
  - `all`: Affinitize to all cores.
  - `one <core>`: Affinitize to a single specific core.
  - `local`: Affinitize to cores on the local NUMA node.
  - `remote [<node>]`: Affinitize to cores on a remote NUMA node.
  - `custom`: Prompt for custom core assignments.
  - `[0-9]*`: Affinitize to a specific range of cores.

### Detailed Breakdown:

#### 1. **Usage and Initial Checks**:
- The script starts by defining a `usage` function that provides help and examples.
- It checks for the presence of `sed` and exits if not found, as `sed` is required for processing the affinity masks.

#### 2. **Command-Line Parsing**:
- The script parses command-line options to determine the mode of operation (`-s`, `-x`, `-X`) and the affinity mode (`all`, `one`, `local`, `remote`, `custom`, `[0-9]*`).
- It also collects the list of network interfaces to be configured.

#### 3. **Core List and NUMA Node Handling**:
- The script reads the list of online CPU cores from `/sys/devices/system/cpu/online` or from `/proc/cpuinfo`.
- It builds a list of cores for each NUMA node by reading from `/sys/devices/system/node/node*/cpulist`.

#### 4. **Affinity Functions**:
- **`build_mask`**: Constructs the hexadecimal affinity mask for a given core.
- **`show_affinity`**: Displays the current affinity settings for a given interrupt.
- **`set_affinity`**: Sets the affinity for a given interrupt and optionally configures XPS.

#### 5. **Main Affinity Logic (`doaff`)**:
- The script iterates over the interrupts associated with each network interface.
- It assigns each interrupt to a core based on the specified affinity mode.
- It handles multiple Tx/Rx queues per interface and ensures that the number of cores matches the number of interrupts.

#### 6. **Final Checks**:
- The script checks if `irqbalance` is running and warns the user if it is, as `irqbalance` might override the affinity settings.

### Example Usage:
- **Show current settings**: `./set_irq_affinity -s eth1`
- **Affinitize to all cores**: `./set_irq_affinity all eth1 eth2`
- **Affinitize to a single core**: `./set_irq_affinity one 2 eth1`
- **Affinitize to local cores**: `./set_irq_affinity local eth1`
- **Affinitize to remote cores**: `./set_irq_affinity remote eth1`
- **Custom core assignment**: `./set_irq_affinity custom eth1`
- **Affinitize to a specific range of cores**: `./set_irq_affinity 0-7,16-23 eth1`

### Summary:
This script is a powerful tool for fine-tuning network performance by affinitizing interrupts to specific CPU cores. It supports various modes of operation, including showing current settings, configuring XPS, and assigning interrupts to local or remote NUMA nodes. The script is flexible and can be customized for specific use cases, making it a valuable asset for network administrators and performance engineers.

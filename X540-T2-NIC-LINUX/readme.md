lspci
ip link show
lspci
sudo apt update 
sudo apt upgrade 
lspci -k -v
ethtool 
sudo ethtool 
sudo ethtool -h
ifconfig 
dmesg | grep -i "eth" 
dmesg | grep -i "<NIC manufacturer>"
sudo dmesg | grep -i "<NIC manufacturer>"
htop
lspci
dmesg | grep -i "intel"
sudo dmesg | grep -i "intel"
sudo lshw -C network
lsmod | grep ixgbe
dmesg | grep ixgbe
sudo dmesg | grep ixgbe
sudo modprobe ixgbe
cd Downloads/
ls
tar zxf ixgbe-5.21.5.tar.gz
cd ixgbe-5.21.5/src/
make
sudo make install
sudo modprobe ixgbe
lsmod | grep ixgbe
ip link show
sudo dmidecode -t bios
sudo dmidecode -t baseboard
ip link show
lsmod | grep ixgbe
dmesg | grep ixgbe
sudo dmesg | grep ixgbe
sudo apt update 
ip link show
sudo subl /etc/default/grub
sudo update-grub
sudo reboot 
ip link show
cd Downloads/
history 
nmcli device
history 
sudo dmidecode -t baseboard
sudo dmidecode -t bios
sudo -E hw-probe -all -upload
modprobe ixgbe
sudo modprobe ixgbe
lsmod | grep ixgbe
ip a
sudo systemctl restart networking
sudo systemctl status networking
ip route
ping 192.168.1.1
lsmod |grep ixgbe
htop
cd Downloads/
unzip intel-public-key-ixgbe-ko.zip
sudo cp intel-public-key-ixgbe-ko.rsa /usr/share/keys/ixgbe/
mv intel-public-key-ixgbe-ko.rsa intel_pubkey.pem
sudo cp intel_pubkey.pem /usr/share/keys/ixgbe/
sudo mkdir -p /usr/share/keys/ixgbe/
sudo cp intel_pubkey.pem /usr/share/keys/ixgbe/
sudo mokutil --import /usr/share/keys/ixgbe/intel_pubkey.pem
sudo reboot 
ip link show
speedtest
lsmod |grep ixgbe
ping 192.168.1.1
ip route
sudo systemctl status networking
sudo modprobe ixgbe
modprobe ixgbe
nmcli device
dmesg | grep ixgbe
sudo dmesg | grep ixgbe
history 
sudo dmesg | grep ixgbe
sudo reboot 
htop 
speedtest
ip -s link
speedtest
ip -s link


Based on the provided bash history excerpt, here's a step-by-step breakdown of how the Intel X540-T2 NIC was likely made to work:

### 1. **Initial System Checks and Updates:**
   - **`lspci`**: The user initially checks the PCI devices connected to the system to identify the NIC.
   - **`ip link show`**: The user checks the network interfaces to see if the NIC is recognized.
   - **`sudo apt update` and `sudo apt upgrade`**: The user updates the package list and upgrades the system to ensure all packages are up to date.
   - **`lspci -k -v`**: The user checks the kernel drivers in use for the NIC.

### 2. **Identifying the NIC and Kernel Messages:**
   - **`dmesg | grep -i "eth"`**: The user checks the kernel messages for any mentions of "eth" to see if the NIC is being recognized.
   - **`dmesg | grep -i "intel"`**: The user specifically looks for mentions of "intel" in the kernel messages to identify the NIC.
   - **`sudo lshw -C network`**: The user lists detailed information about the network devices, including the NIC.

### 3. **Loading the ixgbe Driver:**
   - **`lsmod | grep ixgbe`**: The user checks if the `ixgbe` driver is already loaded.
   - **`dmesg | grep ixgbe`**: The user checks the kernel messages for any mentions of `ixgbe`.
   - **`sudo modprobe ixgbe`**: The user attempts to load the `ixgbe` driver manually.

### 4. **Compiling and Installing the ixgbe Driver:**
   - **`cd Downloads/`**: The user navigates to the Downloads directory where the driver source code is located.
   - **`tar zxf ixgbe-5.21.5.tar.gz`**: The user extracts the driver source code.
   - **`cd ixgbe-5.21.5/src/`**: The user navigates to the source directory.
   - **`make`**: The user compiles the driver.
   - **`sudo make install`**: The user installs the compiled driver.
   - **`sudo modprobe ixgbe`**: The user attempts to load the newly installed `ixgbe` driver.

### 5. **Configuring the System:**
   - **`sudo dmidecode -t bios` and `sudo dmidecode -t baseboard`**: The user retrieves BIOS and baseboard information.
   - **`sudo subl /etc/default/grub`**: The user edits the GRUB configuration file to ensure the correct kernel parameters are set.
   - **`sudo update-grub`**: The user updates the GRUB configuration.
   - **`sudo reboot`**: The user reboots the system to apply the changes.

### 6. **Post-Reboot Checks and Network Configuration:**
   - **`ip link show`**: The user checks the network interfaces again after the reboot.
   - **`sudo systemctl restart networking`**: The user restarts the networking service.
   - **`sudo systemctl status networking`**: The user checks the status of the networking service.
   - **`ping 192.168.1.1`**: The user tests network connectivity.

### 7. **Handling Secure Boot:**
   - **`unzip intel-public-key-ixgbe-ko.zip`**: The user extracts the Intel public key for the driver.
   - **`sudo cp intel_pubkey.pem /usr/share/keys/ixgbe/`**: The user copies the Intel public key to the appropriate directory.
   - **`sudo mokutil --import /usr/share/keys/ixgbe/intel_pubkey.pem`**: The user imports the Intel public key to the Machine Owner Key (MOK) list to allow the driver to work with Secure Boot enabled.
   - **`sudo reboot`**: The user reboots the system to enroll the new key.

### 8. **Final Checks and Testing:**
   - **`ip link show`**: The user checks the network interfaces again after the reboot.
   - **`speedtest`**: The user tests the network speed to ensure the NIC is functioning correctly.
   - **`ip -s link`**: The user checks the network statistics.

### Summary:
The user followed these steps to get the Intel X540-T2 NIC working:
1. **Identified the NIC** using `lspci` and `dmesg`.
2. **Updated the system** to ensure all packages were up to date.
3. **Compiled and installed the `ixgbe` driver** from source.
4. **Configured the system** by editing the GRUB configuration and rebooting.
5. **Handled Secure Boot** by importing the Intel public key.
6. **Tested the NIC** by checking network interfaces, restarting the networking service, and performing a speed test.

By following these steps, the user was able to get the Intel X540-T2 NIC working on their system.



modinfo ixgbe
filename:       /lib/modules/6.8.0-47-generic/updates/drivers/net/ethernet/intel/ixgbe/ixgbe.ko
version:        5.21.5
license:        GPL
description:    Intel(R) 10GbE PCI Express Linux Network Driver
author:         Intel Corporation, <linux.nics@intel.com>
srcversion:     BCFDD3C367E2C550724E8DA
alias:          pci:v00008086d000057B2sv*sd*bc*sc*i*
depends:        dca
retpoline:      Y
name:           ixgbe
vermagic:       6.8.0-47-generic SMP preempt mod_unload modversions 
parm:           IntMode:Change Interrupt Mode (0=Legacy, 1=MSI, 2=MSI-X), default 2 (array of int)
parm:           InterruptType:Change Interrupt Mode (0=Legacy, 1=MSI, 2=MSI-X), default IntMode (deprecated) (array of int)
parm:           MQ:Disable or enable Multiple Queues, default 1 (array of int)
parm:           DCA:Disable or enable Direct Cache Access, 0=disabled, 1=descriptor only, 2=descriptor and data (array of int)
parm:           RSS:Number of Receive-Side Scaling Descriptor Queues, default 0=number of cpus (array of int)
parm:           VMDQ:Number of Virtual Machine Device Queues: 0/1 = disable (1 queue) 2-16 enable (default=8) (array of int)
parm:           max_vfs:Number of Virtual Functions: 0 = disable (default), 1-63 = enable this many VFs (array of int)
parm:           VEPA:VEPA Bridge Mode: 0 = VEB (default), 1 = VEPA (array of int)
parm:           InterruptThrottleRate:Maximum interrupts per second, per vector, (0,1,956-488281), default 1 (array of int)
parm:           LLIPort:Low Latency Interrupt TCP Port (0-65535) (array of int)
parm:           LLIPush:Low Latency Interrupt on TCP Push flag (0,1) (array of int)
parm:           LLISize:Low Latency Interrupt on Packet Size (0-1500) (array of int)
parm:           LLIEType:Low Latency Interrupt Ethernet Protocol Type (array of int)
parm:           LLIVLANP:Low Latency Interrupt on VLAN priority threshold (array of int)
parm:           FdirPballoc:Flow Director packet buffer allocation level:
			1 = 8k hash filters or 2k perfect filters
			2 = 16k hash filters or 4k perfect filters
			3 = 32k hash filters or 8k perfect filters (array of int)
parm:           AtrSampleRate:Software ATR Tx packet sample rate (array of int)
parm:           FCoE:Disable or enable FCoE Offload, default 1 (array of int)
parm:           MDD:Malicious Driver Detection: (0,1), default 1 = on (array of int)
parm:           LRO:Large Receive Offload (0,1), default 0 = off (array of int)
parm:           allow_unsupported_sfp:Allow unsupported and untested SFP+ modules on 82599 based adapters, default 0 = Disable (array of int)
parm:           dmac_watchdog:DMA coalescing watchdog in microseconds (0,41-10000), default 0 = off (array of int)
parm:           vxlan_rx:VXLAN receive checksum offload (0,1), default 1 = Enable (array of int)
parm:           fwlog_method:FW event logging method. 0=ARQ event logging, 1=UART event logging
 (ushort)

Your `modinfo` output shows that the `ixgbe` driver version 5.21.5 is successfully installed and available with its full range of configurable parameters. Here’s how to make use of this information:

### Key Parameters and Recommendations

The `ixgbe` driver supports several parameters you can configure to optimize performance and stability. Here are some commonly adjusted settings and how to apply them:

1. **Interrupt Mode and Type**:
   - **`IntMode`** and **`InterruptType`**: Changing these settings can improve interrupt handling efficiency.
     - `IntMode=2` and `InterruptType=2` enable **MSI-X**, which is preferred for high-speed NICs.
   
2. **Multiple Queues**:
   - **`MQ`**: Enables or disables multiple queues. For high performance, ensure this is enabled with `MQ=1`.

3. **Direct Cache Access**:
   - **`DCA`**: Direct Cache Access can reduce memory latency. Set to `1` to enable it if your system supports it.

4. **Receive-Side Scaling**:
   - **`RSS`**: Controls the number of descriptor queues, usually set to the number of available CPUs. Adjusting this can help distribute traffic load across CPUs for better performance.

5. **Large Receive Offload**:
   - **`LRO`**: Disabled by default but can be enabled with `LRO=1` to improve performance on large TCP streams. However, it may introduce latency, so enable only if needed.

6. **Allow Unsupported SFP Modules**:
   - **`allow_unsupported_sfp`**: Enables compatibility with third-party SFP+ modules. If you are using Intel-certified SFPs, you can set this to `0`.

### Applying the Settings

#### Option 1: Permanent Settings in `modprobe` Configuration

1. **Edit the Configuration File**:
   ```bash
   sudo nano /etc/modprobe.d/ixgbe.conf
   ```
2. **Add the Options**:
   - For example:
     ```plaintext
     options ixgbe IntMode=2 InterruptType=2 MQ=1 DCA=1 LRO=1 allow_unsupported_sfp=1
     ```
3. **Save and Reload the Driver**:
   ```bash
   sudo modprobe -r ixgbe
   sudo modprobe ixgbe
   ```

#### Option 2: Apply Settings at Boot Time via Kernel Parameters

1. **Edit Grub Configuration**:
   ```bash
   sudo nano /etc/default/grub
   ```
2. **Add the Parameters to `GRUB_CMDLINE_LINUX_DEFAULT`**:
   ```plaintext
   GRUB_CMDLINE_LINUX_DEFAULT="quiet splash ixgbe.IntMode=2 ixgbe.InterruptType=2 ixgbe.MQ=1 ixgbe.DCA=1 ixgbe.LRO=1 ixgbe.allow_unsupported_sfp=1"
   ```
3. **Update Grub and Reboot**:
   ```bash
   sudo update-grub
   sudo reboot
   ```

#### Confirm the Settings

After setting the parameters, verify that they are applied with:
```bash
cat /sys/module/ixgbe/parameters/<parameter_name>
```
Replace `<parameter_name>` with each setting, like `IntMode` or `MQ`.

Using these methods, you can ensure that your Intel X540-T2 is optimized for your system's network environment. Let me know if you need further guidance on specific parameters!

The `modinfo ixgbe` command provides detailed information about the `ixgbe` kernel module, which is the driver for Intel's 10GbE PCI Express network cards. Here's a breakdown of the key information and parameters:

### Key Information:
- **Filename**: The path to the module file.
- **Version**: The version of the driver, which is `5.21.5`.
- **License**: The license under which the driver is distributed, which is GPL.
- **Description**: A brief description of the driver, indicating it is for Intel's 10GbE PCI Express network cards.
- **Author**: The author or maintainer of the driver, which is Intel Corporation.
- **Alias**: A PCI device ID alias that helps the kernel identify the driver for specific hardware.
- **Depends**: Other modules that this module depends on, in this case, `dca`.
- **Retpoline**: Indicates whether the module is retpoline-safe, which is a mitigation against Spectre variant 2.
- **Vermagic**: The kernel version and configuration that this module is compatible with.

### Parameters:
The `ixgbe` module supports several parameters that can be adjusted to fine-tune the behavior of the network card. Here’s a detailed explanation of each parameter:

1. **IntMode/InterruptType**:
   - **Description**: Change Interrupt Mode (0=Legacy, 1=MSI, 2=MSI-X).
   - **Default**: 2 (MSI-X).
   - **Usage**: This parameter allows you to change the interrupt mode used by the NIC. MSI-X (Message Signaled Interrupts eXtended) is generally preferred for better performance.

2. **MQ**:
   - **Description**: Disable or enable Multiple Queues.
   - **Default**: 1 (enabled).
   - **Usage**: This parameter controls whether multiple queues are enabled for the NIC. Multiple queues can improve performance by allowing the NIC to handle more packets in parallel.

3. **DCA**:
   - **Description**: Disable or enable Direct Cache Access.
   - **Default**: 0 (disabled).
   - **Usage**: Direct Cache Access allows the CPU to directly access the NIC's cache, which can improve performance. The value can be 0 (disabled), 1 (descriptor only), or 2 (descriptor and data).

4. **RSS**:
   - **Description**: Number of Receive-Side Scaling Descriptor Queues.
   - **Default**: 0 (number of CPUs).
   - **Usage**: Receive-Side Scaling (RSS) distributes incoming network traffic across multiple CPUs. The default value of 0 means the number of queues will be equal to the number of CPUs.

5. **VMDQ**:
   - **Description**: Number of Virtual Machine Device Queues.
   - **Default**: 8.
   - **Usage**: Virtual Machine Device Queues (VMDQ) allow the NIC to handle traffic for multiple virtual machines. The default value of 8 means 8 queues are enabled.

6. **max_vfs**:
   - **Description**: Number of Virtual Functions.
   - **Default**: 0 (disabled).
   - **Usage**: This parameter controls the number of Virtual Functions (VFs) enabled on the NIC. VFs are used for SR-IOV (Single Root I/O Virtualization).

7. **VEPA**:
   - **Description**: VEPA Bridge Mode.
   - **Default**: 0 (VEB).
   - **Usage**: Virtual Ethernet Port Aggregator (VEPA) mode can be set to 0 (VEB) or 1 (VEPA). VEB is the default and is generally used for bridging.

8. **InterruptThrottleRate**:
   - **Description**: Maximum interrupts per second, per vector.
   - **Default**: 1.
   - **Usage**: This parameter controls the interrupt throttling rate to prevent the CPU from being overwhelmed by interrupts.

9. **LLIPort**:
   - **Description**: Low Latency Interrupt TCP Port.
   - **Default**: Not specified.
   - **Usage**: This parameter specifies the TCP port for low latency interrupts.

10. **LLIPush**:
    - **Description**: Low Latency Interrupt on TCP Push flag.
    - **Default**: Not specified.
    - **Usage**: This parameter controls whether low latency interrupts are triggered on TCP push flags.

11. **LLISize**:
    - **Description**: Low Latency Interrupt on Packet Size.
    - **Default**: Not specified.
    - **Usage**: This parameter specifies the packet size threshold for triggering low latency interrupts.

12. **LLIEType**:
    - **Description**: Low Latency Interrupt Ethernet Protocol Type.
    - **Default**: Not specified.
    - **Usage**: This parameter specifies the Ethernet protocol type for low latency interrupts.

13. **LLIVLANP**:
    - **Description**: Low Latency Interrupt on VLAN priority threshold.
    - **Default**: Not specified.
    - **Usage**: This parameter specifies the VLAN priority threshold for low latency interrupts.

14. **FdirPballoc**:
    - **Description**: Flow Director packet buffer allocation level.
    - **Default**: Not specified.
    - **Usage**: This parameter controls the allocation level for Flow Director packet buffers.

15. **AtrSampleRate**:
    - **Description**: Software ATR Tx packet sample rate.
    - **Default**: Not specified.
    - **Usage**: This parameter controls the sample rate for Adaptive Transmission Rate (ATR) in software.

16. **FCoE**:
    - **Description**: Disable or enable FCoE Offload.
    - **Default**: 1 (enabled).
    - **Usage**: This parameter controls whether Fibre Channel over Ethernet (FCoE) offload is enabled.

17. **MDD**:
    - **Description**: Malicious Driver Detection.
    - **Default**: 1 (on).
    - **Usage**: This parameter controls whether Malicious Driver Detection is enabled.

18. **LRO**:
    - **Description**: Large Receive Offload.
    - **Default**: 0 (off).
    - **Usage**: This parameter controls whether Large Receive Offload is enabled.

19. **allow_unsupported_sfp**:
    - **Description**: Allow unsupported and untested SFP+ modules.
    - **Default**: 0 (Disable).
    - **Usage**: This parameter allows the use of unsupported SFP+ modules on 82599-based adapters.

20. **dmac_watchdog**:
    - **Description**: DMA coalescing watchdog in microseconds.
    - **Default**: 0 (off).
    - **Usage**: This parameter controls the DMA coalescing watchdog timer.

21. **vxlan_rx**:
    - **Description**: VXLAN receive checksum offload.
    - **Default**: 1 (Enable).
    - **Usage**: This parameter controls whether VXLAN receive checksum offload is enabled.

22. **fwlog_method**:
    - **Description**: FW event logging method.
    - **Default**: Not specified.
    - **Usage**: This parameter controls the method for firmware event logging.

### Summary:
The `ixgbe` driver is a powerful and configurable driver for Intel's 10GbE network cards. The parameters allow for fine-tuning of various aspects of the NIC's behavior, including interrupt handling, queue management, and offload features. By adjusting these parameters, you can optimize the performance and functionality of the NIC to suit your specific needs.

To manually sign the `ixgbe` module so it can load with Secure Boot enabled, follow these steps:

### 1. Generate a Signing Key Pair
You need a private key and a public certificate to sign the module. This pair will be used to create a signature that Secure Boot can verify.

```bash
cd /root  # Or another secure location for storing keys
openssl req -new -x509 -newkey rsa:2048 -keyout MOK.priv -outform DER -out MOK.der -nodes -days 36500 -subj "/CN=Module Signing Key"
```

This command generates two files:
- `MOK.priv`: The private key used to sign the module.
- `MOK.der`: The public key certificate used by Secure Boot to validate the signature.

### 2. Enroll the Public Key with the System (Using `mokutil`)
Use `mokutil` to enroll the public key so Secure Boot can recognize and accept the signed module:

```bash
sudo mokutil --import MOK.der
```

- You’ll be prompted to create a password. Remember this password, as it will be required during the next boot to complete the enrollment.

### 3. Reboot and Complete the Enrollment
1. Reboot your system.
2. During boot, the **Machine Owner Key (MOK) Manager** menu should appear.
3. Follow the prompts to **Enroll MOK** and confirm the action by entering the password you created.

### 4. Sign the Module with the Private Key
Once the public key is enrolled, you can sign the `ixgbe` module.

Navigate to the directory where the `ixgbe.ko` module is located (usually in `/lib/modules/$(uname -r)/updates/drivers/net/ethernet/intel/ixgbe/` or a similar path), then run:

```bash
sudo /usr/src/linux-headers-$(uname -r)/scripts/sign-file sha256 /root/MOK.priv /root/MOK.der /lib/modules/$(uname -r)/updates/drivers/net/ethernet/intel/ixgbe/ixgbe.ko
```

### 5. Verify the Module Signature
To confirm that the module has been signed, use:

```bash
sudo modinfo ixgbe | grep sig
```

You should see `signature` information if the module is signed correctly.

### 6. Load the Signed Module
With Secure Boot enabled, load the module normally:

```bash
sudo modprobe ixgbe
```

The signed `ixgbe` module should now load without issues, as Secure Boot can validate the signature. 

This process will ensure that your signed module is accepted on subsequent reboots as well. Let me know if any steps need clarification!

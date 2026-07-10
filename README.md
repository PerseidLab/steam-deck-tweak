do not use this tweak ! it will make your steam deck slow and crash often !  

**steamdeck-tweak-zswap.sh** :  
- disable zram
- enable zswap
- add an 16GB swap file
- set swappiness to 100
- enable MGLRU
- configure memlock limits to 2GB
- enable ntsync kernel module 
- disable cpu security mitigations (optional)
- disable transparent huge pages

check if swap and zram enabled : `swapon --show`  
check zram : `zramctl`  
check zswap : `grep -r . /sys/module/zswap/parameters/enabled` and `grep -r . /sys/kernel/debug/zswap/`   
check swappiness : `sysctl vm.swappiness`  
check if ntsync kernel module is loaded : `lsmod | grep ntsync`  
check if a game is using ntsync : `lsof /dev/ntsync`  
check transparent huge pages status : `cat /sys/kernel/mm/transparent_hugepage/enabled`


**run-proton.sh**  :  

a lightweight bash utility to register Proton as a system-wide handler for Windows executables (.exe) on Linux. This allows you to run Windows applications and games using the Steam Linux Runtime (Sniper) directly from your file manager.  
requirement :  GE-Proton10-29 (or edit the INTERNAL_PROTON_BASE to match your version), Steam Linux Runtime Sniper.  
installation : ``./run-proton.sh --install  ``  
uninstallation : ``./run-proton.sh --uninstall``  
this script uses a single shared wine prefix (~/sharedprotonprefix).  

##################################################
## Base Template have only 1 vcpu and can be overwrited
## base template have only 1GB memory , and can be overwrited
## Base template contains only one system disk, and another disk can be added

## Pre existing Customisation Specification are required and used for IP addressing
## the script place the vm automatically in the cluster on the lees used ESX and on the less used disd

##Changelog
## 20140311 - Remove Gateway parameter
## 20140311 - Remove Subnetmask paramater
## 20140311 - Exclude non acesible Datastore
## 20131101 - Add exclusion of datastore matching pattern

#############################################################################################################
## $NewName          VM name 
## $NewTemplate      Base template 
## $NewCluster       Cluster where the vm will reside   
## $NewNumCpu        number of vcpu
## $NewRAMSizeGB     number of GB memory
## $NewDDriveSizeGB  Size of secondary drive
## $NewVlan          v(mware)lan wher the vm will be connected
## $NewSpecName      Custom specused  ; Must be in form SPEC-Lx-xxx or SPEC-W-xxx
## $NewIpAddress     future ip address,
## $NewFriendly      customfield friendlyname
## $NewDescription   note 



Param (
$NewName, 
$NewTemplate, 
$NewCluster, 
$NewNumCpu,
$NewRAMSizeGB,
$NewDDriveSizeGB,
$NewVlan,
$NewSpecName,
$NewIpAddress,
$NewFriendly,
$NewDescription )



### FUNCTIONS #######################
function inlog ([string] $Tinject, [string] $Tfile )
{
$dt = Get-Date -Format "yyyyMMdd-HH:mm:ss" 
$c = Get-Content $Tfile -ErrorAction SilentlyContinue
$nc = $c +"$dt - $Tinject"
$nc | Set-Content $Tfile
Write-Host $dt $Tinject
}
#################################

## EFFECITVE START
Clear-Host
## Fixed parameters
$listNumCpu = 1, 2, 4
$listRAMSizeGB = 1, 2, 3, 4, 5, 6, 8
$MinSizeDiskGB = 40
$MaxDDriveSizeGB = 200
$MinFreeScpaceGB=40

## Logfile
$logfile = "julesV5Createvm.log"

#### Vcenter
$VC = "My.v.center"
$VCUser = "myuser"
$VCPw = "MyP@ssword"


inlog "XXXXXXXXXX Starting Creation V5 XXXXXXXXXX" $logfile
inlog "PARAMETERS : $NewName, $NewTemplate, $NewCluster, $NewNumCpu, $NewRAMSizeGB, $NewDDriveSizeGB, $NewVlan, $NewSpecName, $NewIpAddress,  $NewFriendly, $NewDescription" $logfile

### Parameter testing 
inlog "Checking parameters " $logfile
if ( $NewName -eq "" ){exit 10}
if ( $NewTemplate -eq "") {exit 11}
if ( $NewCluster -eq "") {exit 12}
if ( $listNumCpu -notcontains $NewNumCpu) {exit 13} 
if ( $listRAMSizeGB -notcontains $NewRAMSizeGB) {exit 14} 
if ( $NewDDriveSizeGB -gt $MaxDDriveSizeGB ) {exit 15} 
if ( $NewVlan -eq "") {exit 16}
if ( $NewSpecName -eq "") {exit 17}
inlog "First parameters checking passed" $logfile


##################
# Add VI-toolkit #
##################
Add-PSsnapin VMware.VimAutomation.Core
Initialize-PowerCLIEnvironment.ps1

Clear-Host
## fixed Parameters

$exitcode = 0
##calcultate parameter
$NewName = $NewName.ToUpper()
$NewCreated = Get-Date -format "yyyyMMdd"

inlog  "Starting Creation Process" $logfile
# ** Verify server names are unique **
inlog "Try to connect with VC" $logfile
$cn = Connect-VIServer -Server $VC -User $VCUser -Password $VCPw -ErrorAction SilentlyContinue
if ($cn){
  inlog "Connected to Vcenter" $logfile

	##CHECK Duplicate machine name
  ## due to the fact that vm can be create without this script, we need to be sure that the name is not used
  ## by matching uppercase name
	inlog "Verifing Vm name" $logfile
	$Go = $true
	$AllVMs = Get-VM | Sort
	$j = 0
	while ($AllVMs[$j]) {
	  If ( $NewName -eq $AllVMs[$j].Name.ToUpper()) {
	    inlog "ERROR: Requested VM name $NewName is in use." $logfile
		  $exitcode= 21
	    $Go = $false
	  } # end If
	$j++
	} 
	# end check duplicate
	
	## check Template name
	inlog "Verifing Template name" $logfile
	$chktpl = Get-Template $NewTemplate -ErrorAction SilentlyContinue
	if ( !$chktpl ) { 
		inlog "ERROR: Template $NewTemplate not found" $logfile
		$Go = $false
		$exitcode = 22
	}

	## check OSSPec Name
	inlog "Verifing Spec name" $logfile
	$chkspec = Get-OSCustomizationSpec $NewSpecName -ErrorAction SilentlyContinue
	if (!$chkspec) {
	inlog "ERROR: OS specification  $NewSpecName not found" $logfile
	$Go = $false
	$exitcode = 23
	}

  ## OS specific 
  ## be carefull this is modifying spec each time
  ##there is a risk of bad concurrency

  if ($NewSpecName.ToUpper().StartsWith("SPEC-LX")) {
          inlog "Modifying OS spec : $NewSpecName "	$logfile
   		    $nic = Get-OSCustomizationSpec $NewSpecName | Get-OSCustomizationNicMapping
		      $Gateway = $nic.defaultgateway
		      $SubnetMask = $nic.SubnetMask

		      Get-OSCustomizationSpec $NewSpecName | Get-OSCustomizationNicMapping  | Set-OSCustomizationNicMapping  -IpMode UseStaticIp -IpAddress $NewIpAddress -SubnetMask $SubnetMask -DefaultGateway $Gateway
          $MinSizeDiskGB = 20          
		     }
	elseif ($NewSpecName.ToUpper().StartsWith("SPEC-W")) {
		    inlog "Modifying OS spec : $NewSpecName "	$logfile
		    
		    $nic = Get-OSCustomizationSpec $NewSpecName | Get-OSCustomizationNicMapping
		    $Dns = $nic.Dns
		    $Gateway = $nic.defaultgateway
		    $SubnetMask = $nic.SubnetMask
		    Get-OSCustomizationSpec $NewSpecName | Get-OSCustomizationNicMapping  | Set-OSCustomizationNicMapping  -IpMode UseStaticIp -IpAddress $NewIpAddress -SubnetMask $SubnetMask -DefaultGateway $Gateway -Dns $Dns 
          $MinSizeDiskGB = 40
        }
  else {
  		inlog "ERROR: Cannot retrieve OS spec" $logfile
	    $Go = $false
	    $exitcode = 23
  }


	## check Cluster Name
	inlog "Verifing Cluster name" $logfile
	$chkcl = Get-Cluster $NewCluster -ErrorAction SilentlyContinue
	if (!$chkcl) { 
		inlog "ERROR: Cluster $NewCluster not found" $logfile
	  $Go = $false
	  $exitcode = 24
	}


	If ($Go -eq $true) {
		inlog "Starting Effective creation of $NewName " $logfile
		
		$NewHost = Get-VMHost -location $NewCluster | Sort $_.MemoryUsageMhz | Select -First 1
		inlog "  ESX : $NewHost " $logfile
	  $SpaceNeeded = ($MinSizeDiskGB + $NewDDriveSizeGB)* 1.1 *1024  # Add 10% result in MB
		$NewDstore = $NewHost | Get-Datastore |Where {$_.Accessible} |Where { ($_.FreespaceMB - $MinFreeScpaceGB*1024) -gt $SpaceNeeded } |sort FreeSpaceMB|Where {$_.name -notlike "ST011CAXIV_074"}|Select -First 1
    if ($NewDstore) {
        inlog "  DS : $NewDstore " $logfile   
    	  New-VM -VMHost $NewHost -Name $NewName -Template $NewTemplate  -Datastore $NewDstore  -Description $NewDescription 
    		Set-VM -Confirm:$false -VM $NewName -NumCpu $NewNumCpu -MemoryMB ([int]$NewRAMSizeGB * 1024) -OSCustomizationSpec $NewSpecName
    		Get-NetworkAdapter -VM $NewName | Set-NetworkAdapter -NetworkName $NewVlan -Confirm:$false
        if ($NewDDriveSizeGB -gt 0){ 
          inlog "Add DataDisk " $logfile
    			New-HardDisk -vm $NewName -CapacityKB ([int]$NewDDriveSizeGB * 1024 * 1024)  -Confirm:$false
    		}
        inlog "Set Custom field" $logfile
    		Set-CustomField -Entity $NewName -Name "VMCreated" -Value $NewCreated 
        # Set-CustomField -Entity $NewName -Name Environment -value $Environment
        # Set-CustomField -Entity $NewName -Name Owner -value $Owner
    
        inlog "Remove USB and Floppy" $logfile
    		Get-FloppyDrive -VM $NewName | Remove-FloppyDrive -Confirm:$false
        Get-UsbDevice -VM $NewName | Remove-UsbDevice -Confirm:$false
    
    		inlog "Start VM" $logfile
    		Start-VM -VM $NewName -Confirm:$false
    
    		inlog "Vm Created: $NewName " $logfile
       }
	     else {
	         inlog "ERROR: Cannot find a free Datastore" $logfile
	         $exitcode = 25
	         }
    }
	  else {
	  inlog "ERROR: Receive a nogo fo creation of $NewName " $logfile
	  }
	  Disconnect-VIServer -Confirm:$false
	}
	else {
	inlog "ERROR: Cannot access to Vcenter" $logfile
	$exitcode = 1
	} 
Disconnect-VIServer -Confirm:$false

inlog "Process ended" $logfile
exit $exitcode

<#
.SYNOPSIS
    Получает VMware UUID виртуальных машин из указанного задания резервного копирования на сервере Veeam
.PARAMETER VeeamServer
    Имя или IP-адрес сервера Veeam
.PARAMETER JobName
    Имя задания резервного копирования
.PARAMETER Credential
    Учетные данные для подключения к серверу Veeam (необязательно)
.EXAMPLE
    Get-VeeamJobVmwareUuid -VeeamServer "veeam01.company.com" -JobName "Prod_actual_7-4-3-3"
.EXAMPLE
    $cred = Get-Credential
    Get-VeeamJobVmwareUuid -VeeamServer "192.168.1.100" -JobName "Mail_7-4-3-3" -Credential $cred
.OUTPUTS
    Массив объектов с информацией о виртуальных машинах и их VMware UUID
#>
function Get-VeeamJobVmwareUuid {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$VeeamServer,       
        [Parameter(Mandatory=$true)][string]$JobName,
        [PSCredential]$Credential
    )

    # Проверяем, установлен ли модуль Veeam
    if (-not (Get-Module -Name Veeam.Backup.PowerShell -ErrorAction SilentlyContinue)) {
        try {
            Import-Module Veeam.Backup.PowerShell -ErrorAction Stop
        }
        catch {
            halt "Модуль Veeam.Backup.PowerShell не найден. Убедитесь, что Veeam Backup & Replication установлен."
        }
    }

    # Массив для результатов
    $results = @()

    try {        
        # Подключаемся к серверу Veeam
        if ( -not (Get-VBRServerSession)) {
            spooLog "Подключаемся к серверу Veeam: $VeeamServer"
            if ($Credential) {
                Connect-VBRServer -Server $VeeamServer -Credential $Credential -ErrorAction Stop
            }
            else {
                Connect-VBRServer -Server $VeeamServer -ErrorAction Stop
            }
        
            spooLog "Успешно подключено к $VeeamServer"
        }

        # Получаем задание
        $job = Get-VBRJob -Name $JobName -ErrorAction Stop
        
        if (-not $job) {
            errorLog "Задание с именем '$JobName' не найдено на сервере $VeeamServer"
            return $null
        }

        spooLog "Обрабатываем задание: $($job.Name)"

        # Получаем объекты из задания
        $objects = $job.GetObjectsInJob()
        
        foreach ($object in $objects) {
            # Для VMware VM
            $vm = $object.GetObject()
            if (($vm.Type -eq "VM") -and ($vm.Platform.Platform -eq "EVmware")) {
                $vcenter=($vm.Info.Path -split '\\')[0]
                $results+= @{
                    moRef = "$($vm.ObjectId)@$vcenter.$($global:defaultDomain)"
                    vmName=$vm.Name
                }
            }
        }

        return $results
    }
    catch {
        errorLog "Ошибка при работе с сервером $VeeamServer : $_"
        return $null
    }
    finally {
        # Отключаемся от сервера
        if (Get-VBRServerSession) {
            Disconnect-VBRServer
        }
    }
}





function Get-VeeamJobs {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$VeeamServer,       
        [PSCredential]$Credential
    )

    # Проверяем, установлен ли модуль Veeam
    if (-not (Get-Module -Name Veeam.Backup.PowerShell -ErrorAction SilentlyContinue)) {
        try {
            Import-Module Veeam.Backup.PowerShell -ErrorAction Stop
        }
        catch {
            halt "Модуль Veeam.Backup.PowerShell не найден. Убедитесь, что Veeam Backup & Replication установлен."
        }
    }

    # Массив для результатов
    $results = @()

    try {
        spooLog "Подключаемся к серверу Veeam: $VeeamServer"
        
        # Подключаемся к серверу Veeam
        if ($Credential) {
            Connect-VBRServer -Server $VeeamServer -Credential $Credential -ErrorAction Stop
        }
        else {
            Connect-VBRServer -Server $VeeamServer -ErrorAction Stop
        }
        
        spooLog "Успешно подключено к $VeeamServer"

        # Получаем задание
        return Get-VBRJob -ErrorAction Stop
    }
    catch {
        errorLog "Ошибка при работе с сервером $VeeamServer : $_"
        return @()
    }
    finally {
        # Отключаемся от сервера
        if (Get-VBRServerSession) {
            Disconnect-VBRServer
        }
    }
}

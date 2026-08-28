#загружает пользователя из АД (ищет только в нужной OU)
#если не находит или находит больше 1, то ругается и выходит
function LoadOUUser {
    param(
        [string]$login,
        [string]$path
    )
    Write-Host "Searchin $login in $path"
	$users = Get-ADUser -Filter {(sAMAccountName -like $login)} -SearchBase $path -properties Name,cn,sn,givenName,DisplayName,sAMAccountname,company,department,title,EmployeeNumber,mail,pager,mobile,telephoneNumber
	$u_count = $users | measure 
	Write-Host -ForegroundColor Green "Найдено пользователей по запросу: $( $u_count.Count )"
	if ( $u_count.count -eq 1) {
		foreach($user in $users) {
			return $user
		}
	} else {
		Write-Host -ForegroundColor Red "Err: Можно работать только с 1 пользователем."
		Exit
	}
}


#приводит список OU к единому виду: массив хэшей @{u_OUDN=...; f_OUDN=...}
#на входе допускаются:
# - массив хэшей: формат $user_OUDNs / $inventory2ad_sync, значение копируется между конфигами
#   как есть, лишние ключи (например stickyOrg) просто игнорируются
# - массив строк или одна строка: это только u_OUDN, f_OUDN остается пустым. Годится там,
#   где перенос учетки не нужен - например при сбросе пароля
function NormalizeOUDNs() {
	param ($OUDNs)

	$result=@()
	foreach ($item in $OUDNs) {
		if ($item -is [System.Collections.IDictionary]) {
			$result+=@{u_OUDN=[string]$item.u_OUDN; f_OUDN=[string]$item.f_OUDN}
		} else {
			$result+=@{u_OUDN=[string]$item; f_OUDN=""}
		}
	}

	#возвращаем через запятую, иначе PS развернет массив из 1 элемента обратно в скаляр
	return ,$result
}


#ищет пользователя в одной OU. Ничего не выводит и скрипт не завершает:
#возвращает учетку либо $null (не найдено / OU недоступна / нашлось больше одной)
function FindOUUser {
	param(
		[string]$login,
		[string]$path
	)

	try {
		$users = @(Get-ADUser -Filter {(sAMAccountName -like $login)} -SearchBase $path -properties Name,cn,sn,givenName,DisplayName,sAMAccountname,company,department,title,EmployeeNumber,mail,pager,mobile,telephoneNumber)
	} catch {
		Write-Host -ForegroundColor Red "Err: не удалось выполнить поиск в [$path]: $( $_.Exception.Message )"
		return $null
	}

	if ($users.Count -eq 1) {
		return $users[0]
	}

	if ($users.Count -gt 1) {
		Write-Host -ForegroundColor Red "Err: в [$path] найдено $( $users.Count ) учеток по запросу <$login>"
	}

	return $null
}


#загружает пользователя из АД, перебирая ВСЕ настроенные OU (формат списка - см. NormalizeOUDNs).
#Найдя ровно одну учетку, выставляет $u_OUDN/$f_OUDN по той паре, в которой она лежит:
#именно их DisableADUser использует для переноса в OU уволенных.
#Если не находит или находит больше 1, то ругается и выходит
function LoadOUsUser {
	param(
		[string]$login,
		$OUDNs
	)

	$found=@()
	foreach ($ou in (NormalizeOUDNs $OUDNs)) {
		if ( -not $ou.u_OUDN) { continue }
		Write-Host "Searchin $login in $( $ou.u_OUDN )"
		$user = FindOUUser $login $ou.u_OUDN
		if ($null -ne $user) {
			$found+=@{user=$user; ou=$ou}
		}
	}

	Write-Host -ForegroundColor Green "Найдено пользователей по запросу: $( $found.Count )"

	if ($found.Count -eq 0) {
		Write-Host -ForegroundColor Red "Err: пользователь <$login> не найден ни в одной из настроенных OU."
		Exit
	}

	if ($found.Count -gt 1) {
		Write-Host -ForegroundColor Red "Err: Можно работать только с 1 пользователем. Найдены: $( ($found | ForEach-Object { $_.user.distinguishedName }) -join '; ' )"
		Exit
	}

	#параметры той OU, в которой лежит учетка, нужны DisableADUser для переноса в OU уволенных
	Set-Variable -Name u_OUDN -Value $found[0].ou.u_OUDN -Scope Script
	Set-Variable -Name f_OUDN -Value $found[0].ou.f_OUDN -Scope Script

	return $found[0].user
}


#загружает пользователя из АД.
#Если в конфиге задан $user_OUDNs - ищет по всем OU из него,
#иначе откатывается на старое поведение: единственная OU в $u_OUDN
function LoadUser([string]$login) {
	if ($user_OUDNs) { return LoadOUsUser $login $user_OUDNs }
	return LoadOUUser $login $u_OUDN
}


#создает пользователя с нужными параметрами
function CreateADUser() {
	param 
	(
		[string]$login,
		[string]$name,
		[string]$passwd,
		[string]$position,
		[string]$mail,
		[string]$phone,
		[string]$pager
	)
	
	Write-Host "Добавляем пользователя $login / $name"
	$name	=$name.trim()
	$names	=$name.split(' ')
	$name_cnt=$names | measure
	if ($name_cnt.Count -eq 3) {
		$name_first=$names[1]+" "+$names[2]
		$name_last=$names[0]
	} else {
		Write-Host 'Err: неправильный формат имени (надо из 3х слов)'
		Exit
	}

	if ($pager -eq 'null') {
		New-ADUser -Name $name -AccountPassword (ConvertTo-SecureString $passwd -AsPlainText -force) -DisplayName $name -EmailAddress $mail -SamAccountName $login -UserPrincipalName ("{0}@{1}" -f $login,$domain) -GivenName $name_first -Surname $name_last -Path $u_OUDN -PasswordNeverExpires $true -Title $position -enabled $true -OfficePhone $phone
	} else {
		New-ADUser -Name $name -AccountPassword (ConvertTo-SecureString $passwd -AsPlainText -force) -DisplayName $name -EmailAddress $mail -SamAccountName $login -UserPrincipalName ("{0}@{1}" -f $login,$domain) -GivenName $name_first -Surname $name_last -Path $u_OUDN -PasswordNeverExpires $true -Title $position -enabled $true -OfficePhone $phone -OtherAttributes @{'Pager'=$pager}
	}
}

#Увольняет пользователя в АД
function DisableADUser() {
	param (
		[object]$user
	)

	$nu_path=$user.distinguishedName.replace($u_OUDN,$f_OUDN)
	$nu_path=$nu_path.substring($nu_path.IndexOf('OU='));

	if ( -not (PrepareOU $nu_path)) {
		Write-Host -ForegroundColor Red "Неудача создания папки для уволенных!"
		Exit
	}


	Write-Host "Генерим пароль..."
	$u_passwd = New-SWRandomPassword -Count 1 -PasswordLength 15 -FirstChar 'ABCEFGHJKLMNPQRSTUVWXYZ' -InputStrings  @('abcdefghijkmnpqrstuvwxyz','23456789', '!,-=(){}_.')
	$u_pass= ConvertTo-SecureString -AsPlainText $u_passwd -force

	Write-Host "Сбрасываем пароль... $u_passwd"
	Set-ADAccountPassword $user -Reset -NewPassword $u_pass

	Write-Host "Отключаем пользователя..."
	Disable-ADAccount $user

	if ( $dismiss_groups.count -gt 0) {
		foreach($groupname in $dismiss_groups) {
			Remove-ADGroupMember -Identity $groupname -Member $user.samaccountname -Confirm:$false
		}
	}


	Write-Host -ForegroundColor Yellow "Перемещаем в $nu_path"
	Move-ADobject $user -Targetpath $nu_path
	
	Log ("User <$($user.sAMAccountname)> deactivated sucessfully.")

}

#Сбрасывает пароль на переданный
function UpdateADUserPwd() {
	param 
	(
		[object]$user,
		[string]$passwd
	)
	
	$u_pass= ConvertTo-SecureString -AsPlainText $passwd -force
	Set-ADAccountPassword $user -NewPassword $u_pass -Reset
}


#возвращает родительскую папку в AD (LDAP путь)
function GetADParent() {
    param
    (
        [string]$path
    )
    
    if ($path.Contains(',OU=')) {
        # - есть родительская OU

        #выкусываем из пути последний OU
        return $path.substring($path.IndexOf(',OU=')+1);
    } else {
        #значит родитель - корень домена
        return $path.substring($path.IndexOf('DC='));
    }
}


#Проверяет что путь есть. Создает если нет
function PrepareOU() {
    param
    (
        [string]$path
    )

    if ([adsi]::Exists("LDAP://$path")) {
        return $true;
    }

    #целевой папки нет, тогда пробуем создать.
    
    #Есть родительская?
    $parent = GetADParent $path;
    if ( -not (PrepareOU $parent)) {
        #проблемы на родительском уровне
        return $false;
    }

    #имя нового OU это часть пути до запятой
    $ou_name = $path.Substring(3,$path.IndexOf(',')-3);

    Write-Host -ForegroundColor Green "Creating New OU $ou_name in $parent"
    New-ADOrganizationalUnit -Name $ou_name -Path $parent
    
    return [adsi]::Exists("LDAP://$path")
}
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

#загружает пользователя из АД (ищет только в нужной OU)
#если не находит или находит больше 1, то ругается и выходит
function LoadUser([string]$login) {return LoadOUUser $login $u_OUDN }


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
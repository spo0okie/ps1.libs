#������ ���������� teampass ����� API
#



#---------------------------------



#base64 �����������
function base64encode() {
	param
	(
		[string]$Text
	)

	#$Bytes = [System.Text.Encoding]::ASCII.GetBytes($Text)
	$Bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
	$EncodedText =[System.Convert]::ToBase64String($Bytes)
	$NoPLus = $EncodedText -replace "\+", "-"
	$NoSlash= $NoPLus -replace "\/", "_"
	return $NoSlash
}


#������ �����
function ReadFolder() {
	param
	(
		[string]$folder_id
	)
	$webReq="$($teampass_api_URL)/read/folder/$($folder_id)?apikey=$($teampass_api_key)"
	$data = ((invoke-WebRequest $webReq -ContentType "text/json; charset=utf-8" -UseBasicParsing).content | convertFrom-Json)
	return $data
}

#����� �����
function FindUserByLogin() {
	param
	(
		[string]$login
	)
	$users = ReadFolder ($teampass_users_folder_id)
	foreach ($user in $users) {
		if ($user.login -eq $login) {
			return $user
		}
	}
	return $null;
}

#����� �����
function UserLogin2Id() {
	param
	(
		[string]$login
	)
	$user = FindUserByLogin $login;
    if ( $user -eq $null ) {
    	return -1
    } else {
			return $user.id
    }
}

function base64User() {
	param
	(
		[string]$login,
		[string]$passwd,
		[string]$mail,
		[string]$name,
		[string]$position
	)
	$b64folder_id = base64encode($teampass_users_folder_id)
	$b64login = base64encode($login)
	$b64mail = base64encode($mail)
	$b64passwd = base64encode($passwd)
	$b64descr = base64encode("$name ($position)")
	$b64empty =  base64encode("")
	#���� �� ������������ ��� ����� ��������� ����� ����� � ������� ��������� ���������
	#<label>;<password>;<description>;<folder id>;<login>;<email>;<url>;<tags>;<any one can modify>
	return "$b64mail;$b64passwd;$b64descr;$b64folder_id;$b64login;$b64mail;$b64empty;$b64empty;$b64empty"
}

#���������� �����
function UserUpd() {
	param
	(
		[string]$item_id,
		[string]$login,
		[string]$passwd,
		[string]$mail,
		[string]$name,
		[string]$position
	)
	$newdata = base64User -login $login -passwd $passwd -mail $mail -name $name -position $position
	$webReq="$($teampass_api_URL)/update/item/$($item_id)/$($newdata)?apikey=$($teampass_api_key)"
	$data = ((invoke-WebRequest $webReq -ContentType "text/json; charset=utf-8" -UseBasicParsing).content)
	$data
}


#���������� �����
function UserAdd() {
	param
	(
		[string]$login,
		[string]$passwd,
		[string]$mail,
		[string]$name,
		[string]$position
	)
	$newdata = base64User -login $login -passwd $passwd -mail $mail -name $name -position $position
	$webReq="$($teampass_api_URL)/add/item/$($newdata)?apikey=$($teampass_api_key)"
	$data = ((invoke-WebRequest $webReq -ContentType "text/json; charset=utf-8" -UseBasicParsing).content)# | convertFrom-Json)
	$data

}


function UserSet() {
	param
	(
		[string]$login,
		[string]$passwd,
		[string]$mail,
		[string]$name,
		[string]$position
	)
	$id = UserLogin2Id ($login)
	if ( -not ($id -eq -1)) {
		UserUpd -item_id $id -login $login -passwd $passwd -mail $mail -name $name -position $position
	} else {
		UserAdd -login $login -passwd $passwd -mail $mail -name $name -position $position
	}
}

function FetchPwInteractive() {
	param
	(
		[string]$u_login,
		[string]$u_passwd
	)

	if ( ($u_passwd -eq "") -or ($u_passwd -eq $null) ){
		$teampass_user = FindUserByLogin $u_login;
		if ( $teampass_user -eq $null ) {
			Write-Host -ForegroundColor Red "������������ $u_login �� ������ � �� teampass"
			$initial_pwd=$false
		} else {
			$u_passwd = $teampass_user.pw
			Write-Host -ForegroundColor Green "������������ $u_login ����� ���������� ������ $u_passwd �� teampass"
			$initial_pwd=$true
		}
	} else { $initial_pwd=$true }

	do {
		if ( $initial_pwd -eq $false ) {
			$u_passwd = invoke-expression "& cscript.exe //Nologo $workdir\pwgen.js"
		}
		Write-Host "��������������� ������ :" $u_passwd
		$initial_pwd=$false
		$pwd_accepted = TimedPrompt "����� ������������� ������, ������� ����� ������� � ������� 5� ���..." 5
	} while	($pwd_accepted)
	return $u_passwd
}
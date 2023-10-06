Function YdxApiResultStr($apiResult) {
	if ($apiResult.success -eq 'ok') {
		return 'OK'
	} else {
		return "ERROR: $($apiResult.error)"
	}
}

function FindMailbox([string]$mail) {

	$login_mail=$mail.split('@')[0];

	#загружаем все акккаунты
	$page=1
	do {
		$api_url="https://$mail_apiUrl/api2/admin/email/list?domain=$mail_domain&page=$page&on_page=20"
		$apiResult=(( 
			invoke-WebRequest -Uri $api_url -Method GET -UseBasicParsing `
			-Headers @{PddToken = $mail_token;} `
		).content | convertFrom-Json) 
		$items_cnt=0
		if ($apiResult.success="ok") {
			foreach ($acc in $apiResult.accounts) {
				$items_cnt++
				#проверяем все аккаунты на совпадение
				#Write-host $acc.login.ToLower().split('@')[0] + " -eq " + $login_mail.ToLower()
				if ($acc.login.ToLower().split('@')[0] -eq $login_mail.ToLower()) {
					return $acc.uid
				} else {
					#если аккаунт не совпал - проверяем есть ли алиасы
					#Write-host $mail.ToLower() " -neq " $acc.login.ToLower()
					if ($acc.aliases -is [array]) {
						#если есть - перебираем и сравниваем
						foreach ($alias in $acc.aliases) {
							if ($alias.ToLower().split('@')[0]  -eq $login_mail.ToLower()) {
								return $acc.uid
							}
						}
					}
				}
			}
		} else {
			Write-host "Yandex API returned err on mailbox read."
			Log ("Yandex API returned err on mailbox search <$login_mail>.")
			Exit
		}
	$page++
	} while ( $items_cnt -gt 0 )
	return $false
}



function CreateMailbox() {
	param 
	(
		[string]$login,
		[string]$name,
		[string]$passwd,
		[string]$position,
		[string]$mail,
		[string]$phone
	)
	
	

	$mail_uid = FindMailbox($mail)

	if ( -not ($mail_uid -eq $false)) {
		Write-host "Почтовый ящик $mail уже существует"
		return
	}	


	$login_mail=$mail.split('@')[0];

	Write-host "Создаем ящик $mail"

	$api_url="https://$mail_apiUrl/api2/admin/email/add"

	$apiResult=((
		invoke-WebRequest -Uri $api_url -Method POST -UseBasicParsing `
		-Headers @{PddToken = $mail_token;} `
		-Body @{
			domain=$mail_domain;
			login=$login_mail;
			password=$passwd;
		}
	).content | convertFrom-Json) 
	$err=YdxApiResultStr $apiResult
	if ($apiResult.success -eq "ok") {
		Write-host "Почтовый ящик успешно создан"
		Log ("Mailbox <$login_mail> created sucessfully. $err")
	} else {
		Write-host "Ошибка создания ящика"
		Log ("Error creating mailbox <$login_mail>. $err")
		Exit
	}

	$api_url="https://$mail_apiUrl/api2/admin/email/edit"

	$name	=$name.trim()
	$names	=$name.split(' ')
	$name_cnt=$names | measure
	if ($name_cnt.Count -eq 3) {
		$name_first=$names[0]+" "+$names[1]
		$name_last=$names[2]
	} else {
		Write-Host 'Err: неправильный формат имени (надо из 3х слов)'
		Exit
	}
	
	$apiResult=(
		(
		invoke-WebRequest -Uri $api_url -Method POST -UseBasicParsing `
		-Headers @{PddToken = $mail_token;} `
		-Body @{
			domain=$mail_domain;
			password=$passwd;
			login=$login_mail;
			iname=$name_first.split(' ')[1];
			fname=$name_first.split(' ')[0];
			enabled='yes';
			birth_date='2000-01-01';
			sex=1;
			hintq='random';
			hinta='A*&DHJSDF&hsdfnnфф8';
		}
	).content | convertFrom-Json) 

	if ($apiResult.success="ok") {
		Write-host "Почтовый ящик успешно заполнен"
		Log ("Mailbox <$login_mail> edited sucessfully.")
	} else {
		Write-host "Ошибка изменения ящика"
		Log ("Error editing mailbox <$login_mail>.")
	}
}



function DisableMailbox() {
	param (
		[string]$mail
	)

	$mail_uid = FindMailbox($mail)

	if ($mail_uid -eq $false) {
		Write-host "Почтовый ящик $mail не существует"
		return $false
	}	

	$api_url="https://$mail_apiUrl/api2/admin/email/edit"
	$apiResult=((
		invoke-WebRequest -Uri $api_url -Method POST -UseBasicParsing `
		-Headers @{
			PddToken = $mail_token;
		} `
		-Body @{
			domain=$mail_domain;
			uid=$mail_uid;
			enabled='no';
		}
	).content | convertFrom-Json) 
	if ($apiResult.success="ok") {
		Write-host "Почтовый ящик успешно заблокирован"
		Log ("Mailbox <$mail> deactivated sucessfully.")
		return $true
	} else {
		Write-host "Ошибка блокировки ящика"
		Log ("Error deactivating mailbox <$mail>.")
		return $false
	}
}


function EnableMailbox() {
	param (
		[string]$mail
	)

	$mail_uid = FindMailbox($mail)

	if ($mail_uid -eq $false) {
		Write-host "Почтовый ящик $mail не существует"
		return $false
	}	

	$api_url="https://$mail_apiUrl/api2/admin/email/edit"
	$apiResult=((
		invoke-WebRequest -Uri $api_url -Method POST -UseBasicParsing `
		-Headers @{
			PddToken = $mail_token;
		} `
		-Body @{
			domain=$mail_domain;
			uid=$mail_uid;
			enabled='yes';
		}
	).content | convertFrom-Json) 
	if ($apiResult.success="ok") {
		Write-host "Почтовый ящик успешно заблокирован"
		Log ("Mailbox <$mail> deactivated sucessfully.")
		return $true
	} else {
		Write-host "Ошибка блокировки ящика"
		Log ("Error deactivating mailbox <$mail>.")
		return $false
	}
}


function UpdPwMailbox() {
	param (
		[string]$mail,
		[string]$passwd
	)

	$mail_uid = FindMailbox($mail)

	if ($mail_uid -eq $false) {
		Write-host "Почтовый ящик $mail не существует"
		return $false
	}	

	$api_url="https://$mail_apiUrl/api2/admin/email/edit"
	$apiResult=((
		invoke-WebRequest -Uri $api_url -Method POST -UseBasicParsing `
		-Headers @{
			PddToken = $mail_token;
		} `
		-Body @{
			domain=$mail_domain;
			uid=$mail_uid;
			password=$passwd;
			enabled='yes';
		}
	).content | convertFrom-Json) 
	if ($apiResult.success="ok") {
		Write-host "Пароль на почтовый ящик успешно изменен"
		Log ("Mailbox <$mail> pwd changed sucessfully.")
		return $true
	} else {
		Write-host "Ошибка изменения пароля ящика"
		Log ("Error mailbox passwd change <$mail>.")
		return $false
	}
}


# списки рассылки ----------------------------------------

function MlAddMailbox() {
	param 
	(
		[string]$mail,
		[string]$ml
	)
	$subscriber=$mail.split('@')[0] + '@' + $mail_domain;	
	$api_url="https://$mail_apiUrl/api2/admin/email/ml/subscribe"
	$apiResult=(( 
		invoke-WebRequest -Uri $api_url -Method POST -UseBasicParsing `
		-Headers @{PddToken = $mail_token;} `
		-Body @{
			domain=$mail_domain;
			maillist=$ml;
			subscriber=$subscriber;
		}
	).content | convertFrom-Json) 
	$err=( YdxApiResultStr $apiresult )
	Log ( "Adding $subscriber to $ml list - " + $err)
}


function MlDelMailbox() {
	param 
	(
		[string]$mail,
		[string]$ml
	)
	$subscriber=$mail.split('@')[0] + '@' + $mail_domain;	
	$api_url="https://$mail_apiUrl/api2/admin/email/ml/unsubscribe"
	$apiResult=(( 
		invoke-WebRequest -Uri $api_url -Method POST -UseBasicParsing `
		-Headers @{PddToken = $mail_token;} `
		-Body @{
			domain=$mail_domain;
			maillist=$ml;
			subscriber=$subscriber;
		}
	).content | convertFrom-Json) 
	Log ( "Removing $subscriber from $ml list - " + $apiResult.success)
}


function MlGetList() {
	param 
	(
		[string]$ml
	)
	
	$api_url="https://$mail_apiUrl/api2/admin/email/ml/subscribers?domain=$mail_domain&maillist=$ml"
	$apiResult=(( 
		invoke-WebRequest -Uri $api_url -Method GET -UseBasicParsing `
		-Headers @{PddToken = $mail_token;} `
	).content | convertFrom-Json) 
	if ($apiResult.success="ok") {
		return $apiResult.subscribers
	}
	Log ("Error getting mailbox list from <$ml>.")
	Exit
}

#ищет ящик в массиве ящиков. сравнивает только логины но не домены
function SearchMbox() {
	param
	(
		[string]$mail,
		[array]$mboxes
	)
	foreach ($mbox in $mboxes) {
		if ($mbox.split('@')[0].ToLower() -eq $mail.split('@')[0].ToLower()) {
			return $true
		}
	}
	return $false
}

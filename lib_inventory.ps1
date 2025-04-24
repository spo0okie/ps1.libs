Add-Type -AssemblyName System.Web

#если мы не подгружаем все компы, то все равно объявляем пустой массив, чтобы можно было проверить подгружены ли
$global:InvComps=@();
$global:InvRequestTimeout=10000;
#отладочная инфа по HTTP(s) запросу
function httpResponseDebugData() {
	param
	(
		[object]$reponse,
		[string]$body=''
	)
	$debugMsg= -join(
		"Response Headers:`n",
		'Status'.PadLeft(30," "), ':', "$([int]$response.StatusCode) - $($response.StatusCode)"
	)

	foreach ($HeaderKey in $response.Headers) {
		if ($HeaderKey -ne "Date" ) {
			$debugMsg = -join (
				$debugMsg , "`n",
				$HeaderKey.PadLeft(30," "),
				':',
				$response.Headers[$HeaderKey]
			)
		}							
	}
	$debugMsg = -join (
		$debugMsg , "`n",
		"$('Body'.PadLeft(30," "))`:$body"
	)

	return $debugMsg
}


#формирует словарь заголовков с BASIC-Auth
function authHeader() {
	param (
		[string]$user,                                                                                                                                                                  
		[string]$password
	)

	$pair = "$($user):$($password)"
	$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
	return "Basic $encodedCreds"	
}

#собирает строку параметров для передачи в GET или 
function paramsString() {
    param (
        $data
    )

    $params=@();

    foreach ($param in $data.keys) {
        $params += "$($param)=$($data[$param])"
    }
    
    return $params -join "&"
}


#обработка ответа и конвертирование в объект
function responseFormatParse() {
    param (
        $response,
        $body
    )

    #пытаемся разобрать данные на основании заявленного типа
    if($response.ContentType -match "application/xml") {
        return [xml]$body
    } elseif($response.ContentType -match "application/json") {
        return $body | ConvertFrom-Json
    } else {
        try {
            return [xml]$body
        } catch {
            return $body | ConvertFrom-Json
        }
    }

}


#запрос данных в инвентори
#запись данных об объекте в БД
function requestInventoryData() {
	param
	(
		[string]$uri,
		[string]$method="GET",
		$data=@{},
		$raw=$false
	)
	#пробуем сделать запрос
	try { 
        #если у нас параметры в командной строке - докидываем
        if (@('GET') -contains $method) {
            $reqParams=paramsString $data
            $uri="$($uri)?$($reqParams)"
        }		
        
        #авторизация
        $auth = authHeader $inventory_user_login $inventory_user_password

		$request = [System.Net.WebRequest]::Create($uri)
        $request.Headers.Add('Authorization',$auth)
        $request.Method=$method;
        $request.Accept="application/json";
        $request.Timeout=$global:InvRequestTimeout;

        # Если нам нужно отправить тело запроса
        if (@('PUT','POST','PATCH') -contains $method) {

            #формируем тело запроса
            $sendBody = paramsString $data
            #собираем набор байт для потоковой передачи
            $binaryBody=[System.Text.Encoding]::UTF8.GetBytes($sendBody);

            #выставляем параметры тела запроса
            $request.ContentType="application/x-www-form-urlencoded"
            $request.ContentLength=$binaryBody.Length;

            #передаем тело запроса
            [System.IO.Stream]$requestStream = [System.IO.Stream]$request.GetRequestStream();
            $requestStream.Write($binaryBody, 0, $binaryBody.Length);
            $requestStream.Flush();
            $requestStream.Close();

        } 

        #получаем ответ
		$response = $request.GetResponse()		
        #получаем поток отвтета
	    $responseStream = $response.GetResponseStream()
        #читалка потока
        $streamReader = New-Object System.IO.StreamReader $responseStream       
	    $body = $streamReader.ReadToEnd()
        $responseStream.Close()

        #если все ок, то отвечаем отфроматированным объектом
        if (@(200,201) -contains $response.StatusCode.Value__) {

			debugLog("$($method): $uri - OK")
			if ($raw) {
				return $body
			} else {
				return responseFormatParse $response $body
			}
			

		} 

        errorLog("$($method) $uri - OK ($($response.StatusCode.Value__))`n$(httpResponseDebugData $response $body)")

	} catch [System.Net.WebException] { #Поймали нормальную WEB Exception, т.е. сервер что-то ответил - ща все покажем что не так

        $response = $_.Exception.Response

        if ($null -eq $response) {

			Write-host $_.Exception
			errorLog $_.Exception.Message

		} else {

			$responseStream = $response.GetResponseStream()
			$streamReader = New-Object System.IO.StreamReader $responseStream
			$body = $streamReader.ReadToEnd()
			if ($_.Exception.Response.StatusCode.Value__ -eq 404) {
				if (-not $global:skip404errors) {errorLog("$($method) $($uri) - ERR $($_.Exception.Response.StatusCode.Value__) // Not found: $($body)")}
			} elseif ($_.Exception.Response.StatusCode.Value__ -eq 422) {
				errorLog("$($method) $($uri) - ERR $($_.Exception.Response.StatusCode.Value__) // Data validation fail: $($body) //DATA: $($sendBody)")
			} else {
				errorLog("$($method) $($uri) - ERR $($_.Exception.Response.StatusCode.Value__) // $($_.Exception.Message)`n$(httpResponseDebugData $response $body)")
			}

		}

	} catch { #Ошибка не со стороны веб-сервера
		debugLog($_.Exception)
	}

    return $false

}


function parseObjectId() {
	param
	(
		$object
	)
	try {
        return $obj.id;
    } catch {
        return -1;
    }	
}


function callInventoryRestMethod() {
	param(
		[string]$method,
		[string]$model,
		[string]$action,
		$params=@{},
		$raw=$false
	)
	return requestInventoryData "$($global:inventory_RESTapi_URL)/$($model)/$action" $method $params $raw
}

#возвращает ID по модели(типу данных) и ее имени
function getInventoryObj() {
	param
	(
		[string]$model,
		[string]$name="",
		$additional=@{}
	)
	if ($name.length -gt 0) {
		$additional['name']=$name;
	}
    return requestInventoryData "$($global:inventory_RESTapi_URL)/$($model)/search" 'GET' $additional
}

#возвращает ID по модели(типу данных) и ее имени
function getInventoryId() {
	param
	(
		[string]$model,
		[string]$name="",
		$additional=@{}
	)
    return parseObjectId (getInventoryObj $model $name $additional)
}


#устанавливает модели(типу данных) с указанным ID набор значений
#надо отметить, что набор значений должен быть достаточным для создания нового экземпляра
#иначе данными можно будет только обновлять имеющуюся модель
function setInventoryData() {
	param
	(
		[string]$model,
		$data
	)
    
	try { 
		$id = [int]$data['id']
	} catch {
		$id = -1
		warningLog("Error reading inventory ID!")
		$data
	}

	if ($id -gt 0) {
		#ИД есть - обновляем
		return requestInventoryData "$($global:inventory_RESTapi_URL)/$model/$id"	"PUT"   $data
	} else {
		#ИД не найден - создаем
        $data.Remove('id'); #убираем невалидный ID
		return requestInventoryData "$($global:inventory_RESTapi_URL)/$model"       "POST"	$data	
	}
}

#заливает объект методом Push (на месте инвентори разберется, это новый или обновить только надо)
function pushInventoryData() {
	param
	(
		[string]$model,
		$data
	)
    
   	return requestInventoryData "$($global:inventory_RESTapi_URL)/$model/push"	"POST"   $data
}

#возвращает объект компа в инвентаризации по FQDN
function getInventoryFqdnComp($fqdn) {
	if ([string]::IsNullOrWhiteSpace($fqdn) -or ($fqdn -eq $false)) {
		return $false
	}
    #пробуем кэш
    if ($global:invComps.length -gt 0) {
        $fqdn=$fqdn.ToLower();
	    foreach ($comp in $global:InvComps) {
		    if ([string]($comp.fqdn).ToLower() -eq $fqdn) {
			    return $comp;
                break;
		    }
	    }
    }
	return getInventoryObj 'comps' $fqdn
}

#проверяет что у переданного $comp (объект из инвентори) имеется нужный FQDN и нужные IP адреса
function compareInventoryFqdnIpComp($comp,$fqdn,$ips) {
	if ([string]::IsNullOrWhiteSpace($fqdn) -or ($fqdn -eq $false)) {
		return $false
	}
	if ( -not $ips) {
		return $false
	}

    #если у нас FQDN
    if ( $fqdn.split('.').length -gt 1) {
        if ( -not ([string]($comp.fqdn).ToLower() -eq $fqdn)) {
            return $false;
        }
    } else {
    #иначе у нас hostname
        #если имя не совпадает, то неудача
        if ( -not ([string]($comp.name).ToLower() -eq $fqdn)) {
            return $false;
        }
    }

    #список IP компа в инвентори
    $compIps=$comp.ip.split("`n")
    #проверяем что каждый из нужных IP есть у компа
    foreach ($ip in $ips) {
        if ( -not $ip.length) {continue;}
        if ( -not ($compIps -contains $ip)) {return $false;}
    }

	return $true;
}

#возвращает объект компа в инвентаризации по FQDN и при наличии всех переданных IP
function getInventoryFqdnIpComp($fqdn,$ips) {
	if ([string]::IsNullOrWhiteSpace($fqdn) -or ($fqdn -eq $false)) {
		return $false
	}
	if ( -not $ips) {
		return $false
	}
    #пробуем кэш
    if ($global:invComps.length -gt 0) {
        $fqdn=$fqdn.ToLower();
	    foreach ($comp in $global:InvComps) {
		    if (compareInventoryFqdnIpComp $comp $fqdn $ips) {
                return $comp;
            }
	    }
    }
	return getInventoryObj 'comps' $fqdn
}

function inventoryCacheAllComps() {
    $global:InvComps=callInventoryRestMethod 'GET' 'comps' 'index' @{'per-page'=0; 'expand'='fqdn,domain'}
    if ($global:InvComps -eq $false) {      
        warningLog "Operating Systems loading error"
    } else {
        spooLog "$( $global:invComps.length ) Operating Systems loaded."
    }
}


#посчитать сколько в инвентори узлов с заданным FQDN
function countInventoryFqdnComps() {
	param(
		[string]$fqdn
	)
	$fqdn=$fqdn.ToLower();
	$count=0;
	foreach ($comp in $global:InvComps) {
		if ($fqdn -eq $comp.fqdn.ToLower()) {
			$count++;
		}
	}
	return $count;
}

#посчитать сколько в инвентори узлов с заданным FQDN
function countInventoryFqdnIPComps() {
	param(
		[string]$fqdn,
        $ips
	)
	$fqdn=$fqdn.ToLower();
	$count=0;
	foreach ($comp in $global:InvComps) {
	    if (compareInventoryFqdnIpComp $comp $fqdn $ips) {
			$count++;
		}
	}
	return $count;
}

#найти в инвентори узел с VM.UUID
function searchInvByVMUUID() {
	param([string]$uuid)
    $result=@()
	$json="{`"VMWare.UUID`":`"$uuid`"}"
	foreach ($comp in $global:InvComps) {
		$links=[string]($comp.external_links);
		if (($links).contains($json)) {
			$result+=$comp;
		}
	}
    if ($result.Length -eq 1) {
        return $result[0];
    }

    if ($result.Length -gt 1) {
		errorLog "VM: $($hostname) (VM: $($_.Name); UUID: $($uuid); IPS: $($ips -join ' ')) Имеется несколько UUID в инвентори $($result.Length): $(($result | Select-Object -ExpandProperty id) -join ', ')"
    }
    
	return $false;
}


#либа собрана из аналогичной на JS при помощи нейросети и потом допилено ручками
#(не работал генеренный код, хоть и был похож на нужный)
class PWGen {
    [int]$maxLength=12
    [bool]$includeCapitalLetter=$true
    [bool]$includeNumber=$true
    [bool]$includeSpecial=$true

    [int]$INCLUDE_NUMBER = 1
    [int]$INCLUDE_SPECIAL = 1 -shl 2
    [int]$INCLUDE_CAPITAL_LETTER = 1 -shl 1

    [int]$CONSONANT = 1
    [int]$VOWEL = 1 -shl 1
    [int]$DIPTHONG = 1 -shl 2
    [int]$NOT_FIRST = 1 -shl 3

    [string]Generate0() {
        $result = ""
        $prev = 0
        $isFirst = $true

        $ELEMENTS = @(
			@( "a",  $this.VOWEL ),
			@( "ae", [int]($this.VOWEL -bor $this.DIPTHONG )),
			@( "ah", [int]($this.VOWEL -bor $this.DIPTHONG )),
			@( "ai", [int]($this.VOWEL -bor $this.DIPTHONG )),
			@( "b",  $this.CONSONANT ),
			@( "c",  $this.CONSONANT ),
			@( "ch", [int]($this.CONSONANT -bor $this.DIPTHONG )),
			@( "d",  $this.CONSONANT ),
			@( "e",  $this.VOWEL ),
			@( "ee", [int]($this.VOWEL -bor $this.DIPTHONG )),
			@( "ei", [int]($this.VOWEL -bor $this.DIPTHONG )),
			@( "f",  $this.CONSONANT ),
			@( "g",  $this.CONSONANT ),
			@( "gh", [int]($this.CONSONANT -bor $this.DIPTHONG -bor $this.NOT_FIRST )),
			@( "h",  $this.CONSONANT ),
			@( "i",  $this.VOWEL ),
			@( "ie", [int]($this.VOWEL -bor $this.DIPTHONG )),
			@( "j",  $this.CONSONANT ),
			@( "k",  $this.CONSONANT ),
			@( "l",  $this.CONSONANT ),
			@( "m",  $this.CONSONANT ),
			@( "n",  $this.CONSONANT ),
			@( "ng", [int]($this.CONSONANT -bor $this.DIPTHONG -bor $this.NOT_FIRST )),
			@( "o",  $this.VOWEL ),
			@( "oh", [int]($this.VOWEL -bor $this.DIPTHONG )),
			@( "oo", [int]($this.VOWEL -bor $this.DIPTHONG )),
			@( "p",  $this.CONSONANT ),
			@( "ph", [int]($this.CONSONANT -bor $this.DIPTHONG )),
			@( "qu", [int]($this.CONSONANT -bor $this.DIPTHONG )),
			@( "r",  $this.CONSONANT ),
			@( "s",  $this.CONSONANT ),
			@( "sh", [int]($this.CONSONANT -bor $this.DIPTHONG )),
			@( "t",  $this.CONSONANT ),
			@( "th", [int]($this.CONSONANT -bor $this.DIPTHONG )),
			@( "u",  $this.VOWEL ),
			@( "v",  $this.CONSONANT ),
			@( "w",  $this.CONSONANT ),
			@( "x",  $this.CONSONANT ),
			@( "y",  $this.CONSONANT ),
			@( "z",  $this.CONSONANT )
        )
        $requested = 0
        if ($this.includeCapitalLetter) {
            $requested = $requested -bor $this.INCLUDE_CAPITAL_LETTER
        }

        if ($this.includeNumber) {
            $requested = $requested -bor $this.INCLUDE_NUMBER
        }

        if ($this.includeSpecial) {
            $requested = $requested -bor $this.INCLUDE_SPECIAL
        }

        if (Get-Random -Minimum 0 -Maximum 2) { $shouldBe = $this.VOWEL } else { $shouldBe = $this.CONSONANT }



        while ($result.Length -lt $this.maxLength) {
            $i = Get-Random -Minimum 0 -Maximum $ELEMENTS.Count
            $str = $ELEMENTS[$i][0]
            $flags = $ELEMENTS[$i][1]

            if (($flags -band $shouldBe) -eq 0) {
                continue
            }

            if ($isFirst -and ($flags -band $this.NOT_FIRST) -ne 0) {
                continue
            }

            if (($prev -band $this.VOWEL) -and ($flags -band $this.VOWEL) -and ($flags -band $this.DIPTHONG)) {
                continue
            }

            if (($result.Length + $str.Length) -gt $this.maxLength) {
                continue
            }

            if ($requested -band $this.INCLUDE_CAPITAL_LETTER) {
                if ($isFirst -or ($flags -band $this.CONSONANT) -and (Get-Random -Minimum 0 -Maximum 10) -gt 3) {
                    $str = $str.Substring(0, 1).ToUpper() + $str.Substring(1)
                    $requested = $requested -band -bnot $this.INCLUDE_CAPITAL_LETTER
                }
            }

            $result += $str

            if ($requested -band $this.INCLUDE_NUMBER) {
                if (-not $isFirst -and (Get-Random -Minimum 0 -Maximum 10) -lt 3) {
                    if (($result.Length + $str.Length) -gt $this.maxLength) {
                        $result = $result.Substring(0, $result.Length - 1)
                    }
                    $result += [string](Get-Random -Minimum 0 -Maximum 10)
                    $requested = $requested -band -bnot $this.INCLUDE_NUMBER

                    $isFirst = $true
                    $prev = 0
                    $shouldBe = if (Get-Random -Minimum 0 -Maximum 2) { $this.VOWEL } else { $this.CONSONANT }
                    continue
                }
            }

            if ($requested -band $this.INCLUDE_SPECIAL) {
                if (-not $isFirst -and (Get-Random -Minimum 0 -Maximum 10) -lt 3) {
                    if (($result.Length + $str.Length) -gt $this.maxLength) {
                        $result = $result.Substring(0, $result.Length - 1)
                    }
                    $possible = "!@#`$^*()-_+?=./:',"
                    $result += $possible[(Get-Random -Minimum 0 -Maximum $possible.Length)]
                    $requested = $requested -band -bnot $this.INCLUDE_SPECIAL

                    $isFirst = $true
                    $prev = 0
                    $shouldBe = if (Get-Random -Minimum 0 -Maximum 2) { $this.VOWEL } else { $this.CONSONANT }
                    continue
                }
            }

            if ($shouldBe -eq $this.CONSONANT) {
                $shouldBe = $this.VOWEL
            } else {
                if (($prev -band $this.VOWEL) -or ($flags -band $this.DIPTHONG) -or (Get-Random -Minimum 0 -Maximum 10) -gt 3) {
                    $shouldBe = $this.CONSONANT
                } else {
                    $shouldBe = $this.VOWEL
                }
            }
            $prev = $flags
            $isFirst = $false
        }

        if ($requested -band ($this.INCLUDE_NUMBER -bor $this.INCLUDE_SPECIAL -bor $this.INCLUDE_CAPITAL_LETTER)) {
            return $null
        }

        return $result
    }

    [string]Generate() {
        $result = $null

        while (-not $result) {
            $result = $this.Generate0()
        }

        return $result
    }
}

# Example of usage
#$pwGen = [PWGen]::new()
#$generatedPassword = $pwGen.Generate()
#Write-Output $generatedPassword
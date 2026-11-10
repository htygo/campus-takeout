$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

$base = 'http://localhost:8080'
$results = New-Object System.Collections.ArrayList

function Check($name, $condition, $detail) {
    $status = if ($condition) { 'PASS' } else { 'FAIL' }
    [void]$results.Add([pscustomobject]@{ Result = $status; Test = $name; Detail = $detail })
    $color = if ($condition) { 'Green' } else { 'Red' }
    Write-Host ("[{0}] {1} :: {2}" -f $status, $name, $detail) -ForegroundColor $color
}

function New-Client {
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $true
    $handler.UseCookies = $true
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.BaseAddress = [Uri]$base
    $client.Timeout = [TimeSpan]::FromSeconds(30)
    return $client
}

function Tok($html) {
    $m = [regex]::Match($html, 'name="_csrf"\s+value="([^"]+)"')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

function Get-Page($client, $path) {
    $resp = $client.GetAsync($path).GetAwaiter().GetResult()
    $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    return @{ Status = [int]$resp.StatusCode; Body = $body }
}

function Post-Form($client, $path, $fields) {
    $pairs = New-Object 'System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,string]]'
    foreach ($k in $fields.Keys) {
        $v = [string]$fields[$k]
        $pairs.Add((New-Object 'System.Collections.Generic.KeyValuePair[string,string]'($k, $v)))
    }
    $content = [System.Net.Http.FormUrlEncodedContent]::new($pairs)
    $resp = $client.PostAsync($path, $content).GetAwaiter().GetResult()
    $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    return @{ Status = [int]$resp.StatusCode; Body = $body; FinalUrl = $resp.RequestMessage.RequestUri.AbsolutePath }
}

function Get-CsrfFrom($client, $path) {
    $p = Get-Page $client $path
    return (Tok $p.Body), $p
}

function Login($username, $password) {
    $client = New-Client
    $tok, $loginPage = Get-CsrfFrom $client '/login'
    $r = Post-Form $client '/login' @{ username = $username; password = $password; '_csrf' = $tok }
    return @{ Client = $client; Resp = $r; Tok = (Tok $r.Body) }
}

Write-Host "`n===== 1. 登录与认证 =====" -ForegroundColor Cyan
$u = Login 'student' '123456'
Check '顾客 student 登录成功' (($u.Resp.Body -match '我的订单') -and ($u.Resp.FinalUrl -eq '/menu')) "落地页 $($u.Resp.FinalUrl)"

$bad = Login 'student' 'wrongpass'
Check '错误密码被拒绝' ($bad.Resp.Body -match '用户名或密码错误') '显示错误提示'

$adm = Login 'admin' 'admin123'
Check '管理员 admin 登录成功' (($adm.Resp.Body -match '管理后台') -and -not ($adm.Resp.Body -match '我的订单')) '管理员看到后台入口'

Write-Host "`n===== 2. 菜单浏览 =====" -ForegroundColor Cyan
$g = New-Client
$menu = Get-Page $g '/menu'
Check '游客访问菜单' ($menu.Status -eq 200 -and $menu.Body -match '今天想吃点什么') "状态 $($menu.Status)"
Check '显示菜品数据' ($menu.Body -match '红烧牛肉饭') '包含红烧牛肉饭'
Check '显示分类导航' ($menu.Body -match '盖浇饭') '包含盖浇饭分类'
Check '已下架菜品不显示' (-not ($menu.Body -match '南瓜粥')) '南瓜粥(on_sale=0)未出现'

$search = Get-Page $g '/menu?keyword=%E7%89%9B%E8%82%89'
Check '关键字搜索' (($search.Body -match '红烧牛肉饭') -and ($search.Body -match '牛肉拉面') -and -not ($search.Body -match '黄焖鸡米饭')) '搜"牛肉"命中2个，排除黄焖鸡'

$cat = Get-Page $g '/menu?categoryId=4'
Check '按分类过滤' (($cat.Body -match '柠檬茶') -and -not ($cat.Body -match '红烧牛肉饭')) '饮品分类只含饮品'

$detail = Get-Page $g '/dish/1'
Check '菜品详情页' ($detail.Status -eq 200 -and $detail.Body -match '红烧牛肉饭' -and $detail.Body -match '可选口味') '详情页含口味选项'

Write-Host "`n===== 3. 权限隔离 =====" -ForegroundColor Cyan
$ga = Get-Page $g '/admin'
Check '游客访问后台被拦截' ($ga.Body -match '欢迎回来') '被重定向到登录页'

$ua = Get-Page (New-Client) '/admin'
# 顾客访问后台：需要先登录
$uc = Login 'student' '123456'
$ua2 = Get-Page $uc.Client '/admin'
Check '顾客访问后台被拒绝(403)' ($ua2.Status -eq 403) "状态 $($ua2.Status)"

$admHome = Get-Page $adm.Client '/admin'
Check '管理员访问后台正常' ($admHome.Status -eq 200 -and $admHome.Body -match '经营数据看板') "状态 $($admHome.Status)"

Write-Host "`n===== 4. 购物车 =====" -ForegroundColor Cyan
$c = $uc.Client
$tok = $uc.Tok
Check '清空购物车' ((Post-Form $c '/cart/clear' @{ '_csrf' = $tok }).Status -eq 200) '清空成功'

$r = Post-Form $c '/cart/add' @{ dishId = 1; quantity = 2; taste = '微辣'; '_csrf' = $tok }
Check '加入购物车' ($r.Body -match '已加入购物车') '成功提示'

$r = Post-Form $c '/cart/add' @{ dishId = 1; quantity = 2; taste = '微辣'; '_csrf' = $tok }
$cart = Get-Page $c '/cart'
Check '同菜品同口味数量合并' ($cart.Body -match 'value="4"') '数量合并为 4'

$r = Post-Form $c '/cart/add' @{ dishId = 1; quantity = 1; taste = '特辣'; '_csrf' = $tok }
$cart = Get-Page $c '/cart'
# 每行有"更新"和"删除"两个表单都会带 itemId，所以按去重后的 itemId 值计数
$ids = [regex]::Matches($cart.Body, 'name="itemId" value="(\d+)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
$rowCount = @($ids).Count
Check '不同口味分为两行' ($rowCount -eq 2) "购物车 $rowCount 行（itemId: $($ids -join ',')）"

$r = Post-Form $c '/cart/add' @{ dishId = 14; quantity = 1; taste = '少糖'; '_csrf' = $tok }
Check '下架菜品无法加购' ($r.Body -match '已售罄或已下架') '返回售罄提示'

$r = Post-Form $c '/cart/add' @{ dishId = 11; quantity = 9999; taste = '标准糖'; '_csrf' = $tok }
Check '超库存加购被拦截' ($r.Body -match '库存不足') '返回库存不足'

Write-Host "`n===== 汇总 =====" -ForegroundColor Cyan
$pass = ($results | Where-Object Result -eq 'PASS').Count
$fail = ($results | Where-Object Result -eq 'FAIL').Count
Write-Host ("通过 {0} 项 / 失败 {1} 项" -f $pass, $fail) -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
# CI 用：有失败项时以非零退出码让流水线变红
if ($fail -gt 0) { exit 1 }

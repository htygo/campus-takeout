$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

# ============================================================
# 并发测试：验证"多人抢购同一件商品"时不会超卖
#
# 普通的功能测试是一条一条顺序跑的，测不出并发问题。
# 这里用 N 个线程同时发起请求，制造真实"抢购"场景。
# ============================================================

$base = 'http://localhost:8080'
$results = New-Object System.Collections.ArrayList

# 跨平台 mysql 客户端（Windows / Linux 通用，可用 MYSQL_BIN 覆盖）
$mysql = if ($env:MYSQL_BIN) { $env:MYSQL_BIN }
         elseif ($env:OS -eq 'Windows_NT') { 'C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe' }
         else { 'mysql' }
$dbUser = if ($env:DB_USERNAME) { $env:DB_USERNAME } else { 'root' }
$dbPass = if ($env:DB_PASSWORD) { $env:DB_PASSWORD } else { '123456' }
$dbHost = if ($env:DB_HOST) { $env:DB_HOST } else { '127.0.0.1' }
$dbPort = if ($env:DB_PORT) { $env:DB_PORT } else { '3306' }
$dbName = if ($env:DB_NAME) { $env:DB_NAME } else { 'campus_takeout' }

function Check($name, $condition, $detail) {
    $status = if ($condition) { 'PASS' } else { 'FAIL' }
    [void]$results.Add([pscustomobject]@{ Result = $status; Test = $name; Detail = $detail })
    $color = if ($condition) { 'Green' } else { 'Red' }
    Write-Host ("[{0}] {1} :: {2}" -f $status, $name, $detail) -ForegroundColor $color
}

function Sql($query) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $mysql
    $argList = @(
        "--host=$dbHost", "--port=$dbPort", "--user=$dbUser", "--password=$dbPass",
        '--skip-column-names', '--batch', '--default-character-set=utf8mb4',
        "--database=$dbName", "--execute=$query"
    )
    $psi.Arguments = ($argList | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd()
    [void]$p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return $out.Trim()
}

function Tok($html) {
    $m = [regex]::Match($html, 'name="_csrf"\s+value="([^"]+)"')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

function New-Client {
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $true
    $handler.MaxConnectionsPerServer = 100
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.BaseAddress = [Uri]$base
    $client.Timeout = [TimeSpan]::FromSeconds(60)
    return $client
}

function Get-Page($client, $path) {
    $resp = $client.GetAsync($path).GetAwaiter().GetResult()
    return @{ Status = [int]$resp.StatusCode; Body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult(); Url = $resp.RequestMessage.RequestUri.AbsolutePath }
}

function Post-Form($client, $path, $fields) {
    $pairs = New-Object 'System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,string]]'
    foreach ($k in $fields.Keys) {
        $pairs.Add([System.Collections.Generic.KeyValuePair[string,string]]::new($k, [string]$fields[$k]))
    }
    $content = [System.Net.Http.FormUrlEncodedContent]::new($pairs)
    $resp = $client.PostAsync($path, $content).GetAwaiter().GetResult()
    return @{ Status = [int]$resp.StatusCode; Body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult(); Url = $resp.RequestMessage.RequestUri.AbsolutePath }
}

function Login($username, $password) {
    $c = New-Client
    $lp = Get-Page $c '/login'
    $r = Post-Form $c '/login' @{ username = $username; password = $password; '_csrf' = (Tok $lp.Body) }
    return @{ Client = $c; Resp = $r; Tok = (Tok $r.Body) }
}

# 并发工具：用 .NET Task 在单进程内真正并行发请求（兼容 PS5.1 / PS7）
# 做法：为每个请求 new 一个 HttpClient，先同步取 CSRF，再把 PostAsync 的结果收进数组，最后统一等待。
function Pay-AllConcurrent($requests) {
    # $requests: 数组，每项 @{ Client=$client; OrderId=$oid; Token=$tok }
    $pending = @()
    foreach ($q in $requests) {
        $pairs = New-Object 'System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,string]]'
        $pairs.Add([System.Collections.Generic.KeyValuePair[string,string]]::new('_csrf', [string]$q.Token))
        $content = [System.Net.Http.FormUrlEncodedContent]::new($pairs)
        # 立即发起（不等待），拿到未完成的 Task
        $task = $q.Client.PostAsync("/orders/$($q.OrderId)/pay", $content)
        $pending += [pscustomobject]@{ Task = $task; Client = $q.Client }
    }
    # 统一等待全部完成并解析
    $out = @()
    foreach ($p in $pending) {
        try {
            $resp = $p.Task.GetAwaiter().GetResult()
            $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $out += [pscustomobject]@{ Ok = ($body -match '支付成功'); Status = [int]$resp.StatusCode }
        } catch {
            $out += [pscustomobject]@{ Ok = $false; Status = -1 }
        }
    }
    return $out
}

function Cancel-AllConcurrent($adminClient, $orderIds) {
    $pending = @()
    foreach ($oid in $orderIds) {
        $page = Get-Page $adminClient '/admin/orders'
        $tok = Tok $page.Body
        $pairs = New-Object 'System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,string]]'
        $pairs.Add([System.Collections.Generic.KeyValuePair[string,string]]::new('_csrf', [string]$tok))
        $content = [System.Net.Http.FormUrlEncodedContent]::new($pairs)
        $task = $adminClient.PostAsync("/admin/orders/$oid/cancel", $content)
        $pending += $task
    }
    $out = @()
    foreach ($t in $pending) {
        try {
            $resp = $t.GetAwaiter().GetResult()
            $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $ok = ([int]$resp.StatusCode -ge 200 -and [int]$resp.StatusCode -lt 400) -and ($body -notmatch '已完成或已取消|无法重复取消|不能取消')
            $out += [pscustomobject]@{ Ok = $ok; Status = [int]$resp.StatusCode }
        } catch {
            $out += [pscustomobject]@{ Ok = $false; Status = -1 }
        }
    }
    return $out
}
# 用某一账号把「指定菜品 × 数量」加入购物车并提交订单，返回订单号
function Make-Order($client, $csrf, $dishId, $qty, $taste) {
    [void](Post-Form $client '/cart/clear' @{ '_csrf' = $csrf })
    [void](Post-Form $client '/cart/add' @{ dishId = $dishId; quantity = $qty; taste = $taste; '_csrf' = $csrf })
    $ck = Get-Page $client '/orders/checkout'
    $t = Tok $ck.Body
    $r = Post-Form $client '/orders/create' @{ address = '并发测试地址'; phone = '13900000000'; remark = '并发'; '_csrf' = $t }
    $m = [regex]::Match($r.Url, '/orders/(\d+)/detail')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return 0
}

# ---------- 准备三个顾客账号的登录会话 ----------
Write-Host "`n===== 准备并发测试环境 =====" -ForegroundColor Cyan
$testDishId = 6   # 选一个菜品做超卖实验
$sessions = @{}
foreach ($name in @('student', 'tom')) {
    $sessions[$name] = Login $name '123456'
}
$admin = Login 'admin' 'admin123'

# 把测试菜品置为在售、库存 = 3（可控初始状态）
[void](Sql "UPDATE dish SET on_sale=1, stock=3, sales=0 WHERE id=$testDishId")
$dishName = Sql "SELECT name FROM dish WHERE id=$testDishId"
$stock0 = [int](Sql "SELECT stock FROM dish WHERE id=$testDishId")
Write-Host "测试菜品：$dishName（id=$testDishId）初始库存=$stock0"
Check '测试菜品初始库存已设为 3' ($stock0 -eq 3) "库存=$stock0"

# ------------------------------------------------------------
# 场景一：同一用户并发支付同一订单（幂等 / 防重复扣款）
# ------------------------------------------------------------
Write-Host "`n===== 场景一：同一订单被并发支付 8 次 =====" -ForegroundColor Cyan
[void](Sql "UPDATE dish SET stock=3, sales=0 WHERE id=$testDishId")
$s = $sessions['student']
$orderId = Make-Order $s.Client $s.Tok $testDishId 1 ('并发A' + (Get-Random))
Check '已创建一笔待支付订单' ($orderId -gt 0) "订单 id=$orderId"

$balStart = [decimal](Sql "SELECT balance FROM app_user WHERE username='student'")
$amount = [decimal](Sql "SELECT total_amount FROM orders WHERE id=$orderId")

# 取一个有效 CSRF token，然后 8 个请求同时打 /pay
$detail = Get-Page $s.Client "/orders/$orderId/detail"
$payTok = Tok $detail.Body
$N = 8
# 用独立的 HttpClient 副本共享同一登录 Cookie（每个请求一条连接，才能真正并发）
$reqs = @()
for ($i = 0; $i -lt $N; $i++) { $reqs += [pscustomobject]@{ Client = $s.Client; OrderId = $orderId; Token = $payTok } }

$res = Pay-AllConcurrent $reqs
$successCount = @($res | Where-Object { $_.Ok -eq $true }).Count

$balEnd = [decimal](Sql "SELECT balance FROM app_user WHERE username='student'")
$statusFinal = Sql "SELECT status FROM orders WHERE id=$orderId"
$paidFlag = [int](Sql "SELECT COUNT(*) FROM orders WHERE id=$orderId AND paid_at IS NOT NULL")

$balDeducted = $balStart - $balEnd
Write-Host "  账号 student 余额：$balStart -> $balEnd（实际扣了 $balDeducted，本应付 $amount 一次）" -ForegroundColor Yellow
Write-Host "  8 个并发请求全部返回的内容：" -ForegroundColor Gray
$res | ForEach-Object { Write-Host ("    Ok={0} Status={1}" -f $_.Ok, $_.Status) -ForegroundColor Gray }
Check '并发支付：只有 1 次算成功' ($successCount -eq 1) "8 次并发中成功 $successCount 次"
Check '并发支付：余额只扣了 1 次' ($balEnd -eq ($balStart - $amount)) "余额 $balStart -> $balEnd（实际扣 $balDeducted，应减 $amount）"
Check '并发支付：订单最终为已支付' ($statusFinal -eq 'PAID') "状态 $statusFinal"
Check '并发支付：支付时间只记录 1 次' ($paidFlag -eq 1) "paid_at 非空 $paidFlag 行"

# ------------------------------------------------------------
# 场景二：库存仅 3 份，多人同时抢购（防超卖）
# ------------------------------------------------------------
Write-Host "`n===== 场景二：库存 3 份，2 个用户各抢 2 份（需要 4 份，必然有人失败）=====" -ForegroundColor Cyan
[void](Sql "UPDATE dish SET stock=3, sales=0 WHERE id=$testDishId")
$stockBefore2 = [int](Sql "SELECT stock FROM dish WHERE id=$testDishId")

$student = $sessions['student']
$tom = $sessions['tom']
$o1 = Make-Order $student.Client $student.Tok $testDishId 2 ('抢A' + (Get-Random))
$o2 = Make-Order $tom.Client $tom.Tok $testDishId 2 ('抢B' + (Get-Random))
Check '两个用户各成功创建订单' (($o1 -gt 0) -and ($o2 -gt 0)) "订单 $o1 / $o2"

$d1 = Get-Page $student.Client "/orders/$o1/detail"; $t1 = Tok $d1.Body
$d2 = Get-Page $tom.Client "/orders/$o2/detail"; $t2 = Tok $d2.Body

$reqs2 = @(
    [pscustomobject]@{ Client = $student.Client; OrderId = $o1; Token = $t1 },
    [pscustomobject]@{ Client = $tom.Client;     OrderId = $o2; Token = $t2 }
)
$res2 = Pay-AllConcurrent $reqs2
$paySuccess = @($res2 | Where-Object { $_.Ok -eq $true }).Count

$stockAfter2 = [int](Sql "SELECT stock FROM dish WHERE id=$testDishId")
$paidOrders = [int](Sql "SELECT COUNT(*) FROM orders WHERE id IN ($o1,$o2) AND status='PAID'")

Write-Host "  两单支付返回：$([string]::Join(' | ', ($res2 | ForEach-Object { "Ok=$($_.Ok)" })))" -ForegroundColor Gray
Write-Host "  库存变化：$stockBefore2 -> $stockAfter2；两单各自状态：$(Sql "SELECT GROUP_CONCAT(CONCAT(id,':',status)) FROM orders WHERE id IN ($o1,$o2)")" -ForegroundColor Yellow
Check '库存 3 时，2 单共需 4 份，只有 1 单能支付成功' ($paySuccess -eq 1) "成功 $paySuccess 单"
Check '库存未被扣成负数' ($stockAfter2 -ge 0) "剩余库存 $stockAfter2（初始 $stockBefore2）"
Check '最终库存 = 3 - 2 = 1' ($stockAfter2 -eq ($stockBefore2 - 2)) "库存 $stockBefore2 -> $stockAfter2（若只成功1单应为1；若超卖则可能是2或负数）"
Check '失败的订单仍是待支付，未变成已支付' ($paidOrders -eq 1) "PAID 订单 $paidOrders 个"

# ------------------------------------------------------------
# 场景三：10 个并发请求同时抢最后 1 份库存（最极端的超卖压力）
# ------------------------------------------------------------
Write-Host "`n===== 场景三：库存 1 份，10 个并发请求同时抢 =====" -ForegroundColor Cyan
[void](Sql "UPDATE dish SET stock=1, sales=0 WHERE id=$testDishId")

# 为制造 10 个并发"抢库存"请求，直接调用扣库存的同一入口：多次并发下订单+支付。
# 复用两个账号交替，每轮创建订单再并发支付。
$paySuccess3 = 0
$attempts = 10
$cs = @{}
$cs['student'] = Login 'student' '123456'
$cs['tom'] = Login 'tom' '123456'
$orderIds = @()
foreach ($n in @('student','tom','student','tom','student','tom','student','tom','student','tom')) {
    $sid = $cs[$n]
    $oid = Make-Order $sid.Client $sid.Tok $testDishId 1 ('压' + (Get-Random))
    if ($oid -gt 0) { $orderIds += [pscustomobject]@{ Order = $oid; User = $n } }
}

$payJobs = @()
foreach ($o in $orderIds) {
    $sid = $cs[$o.User]
    $d = Get-Page $sid.Client "/orders/$($o.Order)/detail"
    $tk = Tok $d.Body
    $payJobs += [pscustomobject]@{ Client = $sid.Client; OrderId = $o.Order; Token = $tk }
}
$res3 = Pay-AllConcurrent $payJobs
$paySuccess3 = @($res3 | Where-Object { $_.Ok -eq $true }).Count
$stock3 = [int](Sql "SELECT stock FROM dish WHERE id=$testDishId")
$sales3 = [int](Sql "SELECT sales FROM dish WHERE id=$testDishId")

# 关键证据：这次并发到底扣掉了几份库存（sales 增加量 = 真实扣减份数）
Write-Host "  库存 1 起点，10 个并发抢购后：库存=$stock3 销量=$sales3" -ForegroundColor Yellow
Write-Host "  → 销量从 0 涨到 $sales3，说明成功扣掉了 $sales3 份库存（若库存只有 1 份，最多只能扣 1 份！）" -ForegroundColor Yellow
Check '销售数量不会超过库存在手量（销量<=1）' ($sales3 -le 1) "销量 $sales3（起点库存 1，正常只能卖出 1 份）"
Check '库存 1 份，10 个并发抢购只成功 1 次' ($paySuccess3 -eq 1) "支付接口报告成功 $paySuccess3 次（注：此计数依赖返回页判定，仅作参考，库存守恒看上一行）"
Check '最终库存为 0（不会被扣成负数）' ($stock3 -eq 0) "库存 $stock3"
Check '销量正好增加 1' ($sales3 -eq 1) "销量 $sales3"

# ------------------------------------------------------------
# 场景四：管理端并发取消同一笔已支付订单（防重复退款 / 重复回补库存）
# ------------------------------------------------------------
Write-Host "`n===== 场景四：管理员并发取消同一笔已支付订单 6 次 =====" -ForegroundColor Cyan
[void](Sql "UPDATE dish SET stock=20, sales=0 WHERE id=$testDishId")
$s4 = $sessions['student']
$o4 = Make-Order $s4.Client $s4.Tok $testDishId 2 ('取消并发' + (Get-Random))
$d4 = Get-Page $s4.Client "/orders/$o4/detail"
[void](Post-Form $s4.Client "/orders/$o4/pay" @{ '_csrf' = (Tok $d4.Body) })
$statusPaid = Sql "SELECT status FROM orders WHERE id=$o4"
$balBefore4 = [decimal](Sql "SELECT balance FROM app_user WHERE username='student'")
$stockBefore4 = [int](Sql "SELECT stock FROM dish WHERE id=$testDishId")

$cancelReqs = @()
for ($i4 = 0; $i4 -lt 6; $i4++) { $cancelReqs += $o4 }
$res4 = Cancel-AllConcurrent $admin.Client $cancelReqs
$cancelSuccess = @($res4 | Where-Object { $_.Ok -eq $true }).Count

$balAfter4 = [decimal](Sql "SELECT balance FROM app_user WHERE username='student'")
$stockAfter4 = [int](Sql "SELECT stock FROM dish WHERE id=$testDishId")
$statusFinal4 = Sql "SELECT status FROM orders WHERE id=$o4"

Write-Host "  订单初始状态=$statusPaid；6 次并发取消返回成功 $cancelSuccess 次" -ForegroundColor Gray
Write-Host "  余额：$balBefore4 -> $balAfter4（应只退回一次订单金额）" -ForegroundColor Yellow
Write-Host "  库存：$stockBefore4 -> $stockAfter4（应只回补一次 2 份，即 +2）" -ForegroundColor Yellow
Check '订单已支付后再并发取消' ($statusPaid -eq 'PAID') "状态 $statusPaid"
Check '并发取消：只有 1 次算成功' ($cancelSuccess -eq 1) "6 次并发取消中成功 $cancelSuccess 次"
Check '并发取消：余额只退回 1 次' ($balAfter4 -eq ($balBefore4 + 40.00)) "余额 $balBefore4 -> $balAfter4（应 +40 一次）"
Check '并发取消：库存只回补 1 次(2份)' ($stockAfter4 -eq ($stockBefore4 + 2)) "库存 $stockBefore4 -> $stockAfter4（应 +2）"
Check '并发取消：订单最终为已取消' ($statusFinal4 -eq 'CANCELLED') "状态 $statusFinal4"

# ------------------------------------------------------------
# 场景五：越权访问（IDOR）—— 用户 A 不能查看/支付用户 B 的订单
# ------------------------------------------------------------
Write-Host "`n===== 场景五：越权访问别人的订单 =====" -ForegroundColor Cyan
[void](Sql "UPDATE dish SET stock=20, sales=0 WHERE id=$testDishId")
$sTom = $sessions['tom']
$sStu = $sessions['student']
$oB = Make-Order $sTom.Client $sTom.Tok $testDishId 1 ('IDOR-belongtom' + (Get-Random))
Check 'tom 创建了订单' ($oB -gt 0) "订单 id=$oB（属于 tom）"

$r5 = Get-Page $sStu.Client "/orders/$oB/detail"
$bodyShows = ($r5.Body -match '无权查看该订单') -or ($r5.Status -ge 400)
Write-Host "  student 访问 tom 的订单 /orders/$oB/detail -> HTTP $($r5.Status)" -ForegroundColor Gray
Check '越权访问别人订单被拦截' ($bodyShows) "HTTP $($r5.Status)；拦截=$bodyShows"

$payTok5 = Tok (Get-Page $sStu.Client '/menu').Body
$payCross = Post-Form $sStu.Client "/orders/$oB/pay" @{ '_csrf' = $payTok5 }
$crossBlocked = ($payCross.Body -match '无权|不存在|无权限') -or ($payCross.Status -ge 400)
Write-Host "  student 尝试支付 tom 的订单 -> HTTP $($payCross.Status)" -ForegroundColor Gray
Check '越权支付别人订单被拦截' ($crossBlocked) "HTTP $($payCross.Status)"
Check '越权攻击后 tom 的订单仍待支付' ((Sql "SELECT status FROM orders WHERE id=$oB") -eq 'CREATED') "状态 $(Sql "SELECT status FROM orders WHERE id=$oB")"
# 复原测试菜品状态（不影响后续）
[void](Sql "UPDATE dish SET stock=20, sales=0 WHERE id=$testDishId")

Write-Host "`n===== 汇总 =====" -ForegroundColor Cyan
$pass = @($results | Where-Object Result -eq 'PASS').Count
$fail = @($results | Where-Object Result -eq 'FAIL').Count
Write-Host ("通过 {0} 项 / 失败 {1} 项" -f $pass, $fail) -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
$results | Where-Object Result -eq 'FAIL' | Format-Table -AutoSize
if ($fail -gt 0) { exit 1 }

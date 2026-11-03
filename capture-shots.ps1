# 用 Chrome DevTools Protocol 驱动浏览器：登录后对主要页面截图
$ErrorActionPreference = 'Stop'
$proj = 'C:\Users\34519\spring-tool-suite-3.9.4.RELEASE-e4.7.3a-win32-x86_64\campus-takeout'
$shots = Join-Path $proj 'screenshots'
New-Item -ItemType Directory -Force $shots | Out-Null
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$port = 9333
$profile = Join-Path $env:TEMP 'chrome-cdp-shots'
$base = 'http://localhost:8080'

# 启动带远程调试的 Chrome
$chromeProc = Start-Process -FilePath $chrome -ArgumentList @(
    '--headless=new', '--disable-gpu', '--no-sandbox', '--hide-scrollbars',
    "--remote-debugging-port=$port", "--user-data-dir=$profile",
    '--window-size=1440,1200', 'about:blank'
) -PassThru
Start-Sleep -Seconds 4

# 等待调试端口就绪
$wsUrl = $null
for ($i = 0; $i -lt 20; $i++) {
    try {
        $tabs = Invoke-RestMethod "http://127.0.0.1:$port/json" -TimeoutSec 3
        $page = $tabs | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
        if ($page) { $wsUrl = $page.webSocketDebuggerUrl; break }
    } catch { Start-Sleep -Milliseconds 500 }
}
if (-not $wsUrl) { throw '无法连接 Chrome 调试端口' }
Write-Host "已连接 CDP: $wsUrl"

# 建立 WebSocket
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.ConnectAsync([Uri]$wsUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult()

$script:msgId = 0
function Send-Cmd($method, $params) {
    $script:msgId++
    $payload = @{ id = $script:msgId; method = $method; params = $params } | ConvertTo-Json -Depth 10 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $seg = New-Object System.ArraySegment[byte] -ArgumentList @(,$bytes)
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
    # 读取直到拿到同 id 的响应
    $buf = New-Object byte[] 33554432
    while ($true) {
        $ms = New-Object System.IO.MemoryStream
        do {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [Threading.CancellationToken]::None).GetAwaiter().GetResult()
            $ms.Write($buf, 0, $r.Count)
        } while (-not $r.EndOfMessage)
        $text = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
        try {
            $obj = $text | ConvertFrom-Json
        } catch { continue }
        if ($obj.id -eq $script:msgId) { return $obj }
    }
}

function Navigate($url) {
    Send-Cmd 'Page.navigate' @{ url = $url } | Out-Null
    Start-Sleep -Milliseconds 1800
}

function Screenshot($name) {
    $r = Send-Cmd 'Page.captureScreenshot' @{ format = 'png'; captureBeyondViewport = $false }
    $bytes = [Convert]::FromBase64String($r.result.data)
    $path = Join-Path $shots $name
    [System.IO.File]::WriteAllBytes($path, $bytes)
    Write-Host ("  截图 {0}  ({1} KB)" -f $name, [math]::Round($bytes.Length / 1KB))
}

function EvalJs($expr) {
    $r = Send-Cmd 'Runtime.evaluate' @{ expression = $expr; awaitPromise = $true; returnByValue = $true }
    return $r.result.result.value
}

Send-Cmd 'Page.enable' @{} | Out-Null
Send-Cmd 'Runtime.enable' @{} | Out-Null

Write-Host "`n--- 游客页面 ---"
Navigate "$base/menu"
Screenshot '01-menu-guest.png'

Navigate "$base/login"
Screenshot '02-login.png'

Navigate "$base/dish/1"
Screenshot '03-dish-detail.png'

Navigate "$base/register"
Screenshot '04-register.png'

Write-Host "`n--- 顾客登录 ---"
# 通过表单登录（保持同一浏览器会话）
$loginJs = @'
(async () => {
  const res = await fetch('/login', {method:'GET'});
  const html = await res.text();
  const m = html.match(/name="_csrf"\s+value="([^"]+)"/);
  const body = new URLSearchParams({username:'student', password:'123456', _csrf:m[1]});
  const r2 = await fetch('/login', {method:'POST', body:body, redirect:'follow'});
  return r2.status;
})()
'@
Navigate "$base/login"
$st = EvalJs $loginJs
Write-Host "  登录返回状态: $st"

# 加购物车（用页面表单 + CSRF）
$cartJs = @'
(async () => {
  const html = await (await fetch('/menu')).text();
  const m = html.match(/name="_csrf"\s+value="([^"]+)"/);
  const tok = m[1];
  async function add(dishId, qty, taste) {
    const b = new URLSearchParams({dishId:String(dishId), quantity:String(qty), taste:taste, _csrf:tok});
    await fetch('/cart/add', {method:'POST', body:b});
  }
  await fetch('/cart/clear', {method:'POST', body:new URLSearchParams({_csrf:tok})});
  await add(1, 2, '微辣');
  await add(2, 1, '中辣');
  await add(9, 1, '椒盐');
  await add(11, 2, '少糖');
  const r = await fetch('/cart');
  return r.status;
})()
'@
$st = EvalJs $cartJs
Write-Host "  购物车准备: $st"

Navigate "$base/cart"
Screenshot '05-cart.png'

Navigate "$base/orders/checkout"
Screenshot '06-checkout.png'

Navigate "$base/orders"
Screenshot '07-orders.png'

Navigate "$base/me"
Screenshot '08-profile.png'

# 订单详情：查询数据库里该用户最新的已完成订单
$mc = 'C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe'
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'cmd.exe'
$psi.Arguments = '/c ""' + $mc + '" -u root -p123456 -N -B -D campus_takeout -e "SELECT id FROM orders WHERE status=''COMPLETED'' AND user_id=(SELECT id FROM app_user WHERE username=''student'') ORDER BY id DESC LIMIT 1" 2>NUL"'
$psi.RedirectStandardOutput = $true
$psi.UseShellExecute = $false
$proc = [System.Diagnostics.Process]::Start($psi)
$doneOrderId = $proc.StandardOutput.ReadToEnd().Trim()
$proc.WaitForExit()
Write-Host "  已完成订单 ID: $doneOrderId"
if ($doneOrderId) {
    Navigate "$base/orders/$doneOrderId/detail"
    Screenshot '09-order-detail.png'
}
Write-Host "`n--- 管理员后台 ---"
$adminJs = @'
(async () => {
  const html = await (await fetch('/login')).text();
  const m = html.match(/name="_csrf"\s+value="([^"]+)"/);
  const body = new URLSearchParams({username:'admin', password:'admin123', _csrf:m[1]});
  const r2 = await fetch('/login', {method:'POST', body:body, redirect:'follow'});
  return r2.status;
})()
'@
Navigate "$base/login"
$st = EvalJs $adminJs
Write-Host "  管理员登录: $st"

Navigate "$base/admin"
Screenshot '10-admin-dashboard.png'

Navigate "$base/admin/dishes"
Screenshot '11-admin-dishes.png'

Navigate "$base/admin/orders"
Screenshot '12-admin-orders.png'

Navigate "$base/admin/categories"
Screenshot '13-admin-categories.png'

Navigate "$base/admin/dishes/new"
Screenshot '14-admin-dish-form.png'

Navigate "$base/admin/reviews"
Screenshot '15-admin-reviews.png'

$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', [Threading.CancellationToken]::None).GetAwaiter().GetResult()
Stop-Process -Id $chromeProc.Id -Force -ErrorAction SilentlyContinue
Write-Host "`n截图完成，输出目录：$shots"
Get-ChildItem $shots -Filter '*.png' | Select-Object Name, @{n='KB';e={[math]::Round($_.Length/1KB)}} | Format-Table -AutoSize

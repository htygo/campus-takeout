$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

$base = 'http://localhost:8080'
$results = New-Object System.Collections.ArrayList
$mysql = 'C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe'

function Check($name, $condition, $detail) {
    $status = if ($condition) { 'PASS' } else { 'FAIL' }
    [void]$results.Add([pscustomobject]@{ Result = $status; Test = $name; Detail = $detail })
    $color = if ($condition) { 'Green' } else { 'Red' }
    Write-Host ("[{0}] {1} :: {2}" -f $status, $name, $detail) -ForegroundColor $color
}

function Sql($query) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'cmd.exe'
    $psi.Arguments = '/c ""' + $mysql + '" -u root -p123456 -N -B --default-character-set=utf8mb4 -D campus_takeout -e "' + $query + '" 2>NUL"'
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd()
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
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.BaseAddress = [Uri]$base
    $client.Timeout = [TimeSpan]::FromSeconds(30)
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

Write-Host "`n===== 0. 记录初始状态 =====" -ForegroundColor Cyan
$stockBefore = [int](Sql "SELECT stock FROM dish WHERE id=1")
$salesBefore = [int](Sql "SELECT sales FROM dish WHERE id=1")
$balBefore = [decimal](Sql "SELECT balance FROM app_user WHERE username='student'")
Write-Host "红烧牛肉饭 初始库存=$stockBefore 销量=$salesBefore；student 余额=$balBefore"

Write-Host "`n===== 1. 下单流程 =====" -ForegroundColor Cyan
$u = Login 'student' '123456'
$c = $u.Client
$tok = $u.Tok

$r = Post-Form $c '/cart/clear' @{ '_csrf' = $tok }
$r = Post-Form $c '/cart/add' @{ dishId = 1; quantity = 2; taste = '微辣'; '_csrf' = $tok }
Check '准备：加入 2 份牛肉饭' ($r.Body -match '已加入购物车') '加购成功'

$checkout = Get-Page $c '/orders/checkout'
Check '结算页正常' ($checkout.Status -eq 200 -and $checkout.Body -match '收货信息') '显示收货信息表单'

$r = Post-Form $c '/orders/create' @{ address = '东区学生公寓 3 号楼 201'; phone = '13811112222'; remark = '测试订单，不要香菜'; '_csrf' = $tok }
Check '提交订单成功' ($r.Body -match '订单详情' -and $r.Url -match '/orders/\d+/detail') "落地 $($r.Url)"

$orderId = [int]([regex]::Match($r.Url, '/orders/(\d+)/detail').Groups[1].Value)
Check '订单已写入数据库' ([int](Sql "SELECT COUNT(*) FROM orders WHERE id=$orderId") -eq 1) "订单 ID=$orderId"

$orderNo = Sql "SELECT order_no FROM orders WHERE id=$orderId"
Check '订单号已生成' ($orderNo -match '^T\d{18}$') "单号 $orderNo"

$amount = [decimal](Sql "SELECT total_amount FROM orders WHERE id=$orderId")
$expect = 22.00 * 2
Check '订单金额正确' ($amount -eq $expect) "金额 $amount（22×2=$expect）"

$itemCnt = [int](Sql "SELECT COUNT(*) FROM order_item WHERE order_id=$orderId")
Check '订单明细已快照' ($itemCnt -eq 1) "明细 $itemCnt 条"
$snapName = Sql "SELECT dish_name FROM order_item WHERE order_id=$orderId"
Check '明细保存菜名快照' ($snapName -eq '红烧牛肉饭') "快照名 $snapName"

$cartLeft = [int](Sql "SELECT COUNT(*) FROM cart_item WHERE user_id=(SELECT id FROM app_user WHERE username='student')")
Check '下单后购物车已清空' ($cartLeft -eq 0) "剩余 $cartLeft 条"

$statusNow = Sql "SELECT status FROM orders WHERE id=$orderId"
Check '新订单状态为待支付' ($statusNow -eq 'CREATED') "状态 $statusNow"

Write-Host "`n===== 2. 支付与库存扣减 =====" -ForegroundColor Cyan
$detail = Get-Page $c "/orders/$orderId/detail"
$tok = Tok $detail.Body
$r = Post-Form $c "/orders/$orderId/pay" @{ '_csrf' = $tok }
Check '支付成功' ($r.Body -match '支付成功，商家正在备餐') '提示支付成功'

$stockAfter = [int](Sql "SELECT stock FROM dish WHERE id=1")
$salesAfter = [int](Sql "SELECT sales FROM dish WHERE id=1")
Check '库存已扣减 2 份' ($stockAfter -eq $stockBefore - 2) "库存 $stockBefore -> $stockAfter"
Check '销量已增加 2 份' ($salesAfter -eq $salesBefore + 2) "销量 $salesBefore -> $salesAfter"

$balAfter = [decimal](Sql "SELECT balance FROM app_user WHERE username='student'")
Check '余额已扣除订单金额' ($balAfter -eq $balBefore - $expect) "余额 $balBefore -> $balAfter"

$paidAt = Sql "SELECT IFNULL(paid_at,'') FROM orders WHERE id=$orderId"
Check '支付时间已记录' ($paidAt -ne '') "paid_at=$paidAt"
$statusNow = Sql "SELECT status FROM orders WHERE id=$orderId"
Check '订单状态变为已支付' ($statusNow -eq 'PAID') "状态 $statusNow"

$r = Post-Form $c "/orders/$orderId/pay" @{ '_csrf' = (Tok $r.Body) }
Check '重复支付被拦截' ($r.Body -match '无法支付') '第二次支付返回状态错误提示'

Write-Host "`n===== 3. 管理端订单流转 =====" -ForegroundColor Cyan
$a = Login 'admin' 'admin123'
$ac = $a.Client
$atok = $a.Tok

$adminOrders = Get-Page $ac '/admin/orders?status=PAID'
Check '后台按状态筛选订单' ($adminOrders.Body -match $orderNo) "已支付列表含 $orderNo"

$r = Post-Form $ac "/admin/orders/$orderId/advance" @{ '_csrf' = $atok }
Check '已支付 -> 配送中' ((Sql "SELECT status FROM orders WHERE id=$orderId") -eq 'DELIVERING') '状态流转成功'

$r = Post-Form $ac "/admin/orders/$orderId/advance" @{ '_csrf' = $atok }
Check '配送中 -> 已完成' ((Sql "SELECT status FROM orders WHERE id=$orderId") -eq 'COMPLETED') '状态流转成功'

$r = Post-Form $ac "/admin/orders/$orderId/advance" @{ '_csrf' = $atok }
Check '已完成不能再流转' ($r.Body -match '无法继续流转') '返回状态错误提示'

$completedAt = Sql "SELECT IFNULL(completed_at,'') FROM orders WHERE id=$orderId"
Check '完成时间已记录' ($completedAt -ne '') "completed_at=$completedAt"

Write-Host "`n===== 4. 评价 =====" -ForegroundColor Cyan
$detail = Get-Page $c "/orders/$orderId/detail"
$tok = Tok $detail.Body
$r = Post-Form $c "/orders/$orderId/review" @{ rating = 5; content = '味道很好，配送也快！'; '_csrf' = $tok }
Check '提交评价成功' ($r.Body -match '感谢您的评价') '评价提交成功'
$rating = Sql "SELECT rating FROM review WHERE order_id=$orderId"
Check '评价已入库' ($rating -eq '5') "评分 $rating"

$r = Post-Form $c "/orders/$orderId/review" @{ rating = 3; content = '重复评价'; '_csrf' = (Tok $r.Body) }
Check '重复评价被拦截' ($r.Body -match '已经评价过') '返回已评价提示'

Write-Host "`n===== 5. 库存不足回滚（防超卖）=====" -ForegroundColor Cyan
# 把柠檬茶库存改成 1，尝试买 2 份，支付应失败且库存/余额不变
Sql "UPDATE dish SET stock=1 WHERE id=11" | Out-Null
$u2 = Login 'tom' '123456'
$c2 = $u2.Client
$tok2 = $u2.Tok
Post-Form $c2 '/cart/clear' @{ '_csrf' = $tok2 } | Out-Null
Post-Form $c2 '/cart/add' @{ dishId = 11; quantity = 1; taste = '标准糖'; '_csrf' = $tok2 } | Out-Null
$r = Post-Form $c2 '/orders/create' @{ address = '西区 1 号楼'; phone = '13833334444'; '_csrf' = $tok2 } | Out-Null
$oid2 = [int](Sql "SELECT MAX(id) FROM orders WHERE user_id=(SELECT id FROM app_user WHERE username='tom')")
# 再手动把库存改成 0，模拟下单后被别人买走
Sql "UPDATE dish SET stock=0 WHERE id=11" | Out-Null
$bal2Before = [decimal](Sql "SELECT balance FROM app_user WHERE username='tom'")
$tok2 = Tok (Get-Page $c2 "/orders/$oid2/detail").Body
$r = Post-Form $c2 "/orders/$oid2/pay" @{ '_csrf' = $tok2 }
Check '库存不足时支付失败' ($r.Body -match '库存不足') '提示库存不足'
$bal2After = [decimal](Sql "SELECT balance FROM app_user WHERE username='tom'")
Check '支付失败余额未扣' ($bal2After -eq $bal2Before) "余额 $bal2Before -> $bal2After"
$st2 = Sql "SELECT status FROM orders WHERE id=$oid2"
Check '支付失败订单仍待支付' ($st2 -eq 'CREATED') "状态 $st2"
Sql "UPDATE dish SET stock=200 WHERE id=11" | Out-Null
Post-Form $c2 "/orders/$oid2/cancel" @{ '_csrf' = (Tok (Get-Page $c2 "/orders/$oid2/detail").Body) } | Out-Null

Write-Host "`n===== 6. 余额不足拦截 =====" -ForegroundColor Cyan
Sql "UPDATE app_user SET balance=1.00 WHERE username='tom'" | Out-Null
$tok2 = (Tok (Get-Page $c2 '/menu').Body)
Post-Form $c2 '/cart/clear' @{ '_csrf' = $tok2 } | Out-Null
Post-Form $c2 '/cart/add' @{ dishId = 9; quantity = 1; taste = '原味'; '_csrf' = $tok2 } | Out-Null
Post-Form $c2 '/orders/create' @{ address = '西区 1 号楼'; phone = '13833334444'; '_csrf' = $tok2 } | Out-Null
$oid3 = [int](Sql "SELECT MAX(id) FROM orders WHERE user_id=(SELECT id FROM app_user WHERE username='tom')")
$tok2 = Tok (Get-Page $c2 "/orders/$oid3/detail").Body
$r = Post-Form $c2 "/orders/$oid3/pay" @{ '_csrf' = $tok2 }
Check '余额不足时不能支付' ($r.Body -match '余额不足') '提示余额不足'
Sql "UPDATE dish SET stock=stock+1, sales=sales-1 WHERE id=9" | Out-Null
Post-Form $c2 "/orders/$oid3/cancel" @{ '_csrf' = (Tok (Get-Page $c2 "/orders/$oid3/detail").Body) } | Out-Null

Write-Host "`n===== 7. 管理端取消订单退款 =====" -ForegroundColor Cyan
Sql "UPDATE app_user SET balance=200.00 WHERE username='tom'" | Out-Null
$tok2 = Tok (Get-Page $c2 '/menu').Body
Post-Form $c2 '/cart/clear' @{ '_csrf' = $tok2 } | Out-Null
Post-Form $c2 '/cart/add' @{ dishId = 1; quantity = 1; taste = '微辣'; '_csrf' = $tok2 } | Out-Null
Post-Form $c2 '/orders/create' @{ address = '西区 1 号楼'; phone = '13833334444'; '_csrf' = $tok2 } | Out-Null
$oid4 = [int](Sql "SELECT MAX(id) FROM orders WHERE user_id=(SELECT id FROM app_user WHERE username='tom')")
$tok2 = Tok (Get-Page $c2 "/orders/$oid4/detail").Body
Post-Form $c2 "/orders/$oid4/pay" @{ '_csrf' = $tok2 } | Out-Null
$stockPaid = [int](Sql "SELECT stock FROM dish WHERE id=1")
$balPaid = [decimal](Sql "SELECT balance FROM app_user WHERE username='tom'")
$r = Post-Form $ac "/admin/orders/$oid4/cancel" @{ '_csrf' = $atok }
Check '管理员取消已支付订单' ($r.Status -eq 200) '取消成功'
$stockCancel = [int](Sql "SELECT stock FROM dish WHERE id=1")
$balCancel = [decimal](Sql "SELECT balance FROM app_user WHERE username='tom'")
Check '取消后库存已回补' ($stockCancel -eq $stockPaid + 1) "库存 $stockPaid -> $stockCancel"
Check '取消后余额已退款' ($balCancel -eq $balPaid + 22.00) "余额 $balPaid -> $balCancel"
Check '订单状态为已取消' ((Sql "SELECT status FROM orders WHERE id=$oid4") -eq 'CANCELLED') 'CANCELLED'

Write-Host "`n===== 8. 后台菜品管理 =====" -ForegroundColor Cyan
$r = Post-Form $ac '/admin/dishes/save' @{ name = '测试菜'; categoryId = 1; price = '9.90'; stock = 30; description = '自动化测试'; taste = '不辣,微辣'; imageEmoji = '🧪'; onSale = 'true'; '_csrf' = $atok }
Check '新增菜品' ($r.Body -match '菜品已新增') '新增成功'
$newId = [int](Sql "SELECT id FROM dish WHERE name='测试菜' ORDER BY id DESC LIMIT 1")
Check '新菜品出现在前台菜单' ((Get-Page (New-Client) '/menu').Body -match '测试菜') '前台可见'

$r = Post-Form $ac "/admin/dishes/$newId/toggle" @{ '_csrf' = $atok }
Check '下架菜品' ((Sql "SELECT on_sale FROM dish WHERE id=$newId") -eq '0') 'on_sale=0'
Check '下架后前台不可见' (-not ((Get-Page (New-Client) '/menu').Body -match '测试菜')) '前台已隐藏'

$r = Post-Form $ac "/admin/dishes/$newId/restock" @{ quantity = 20; '_csrf' = $atok }
Check '菜品补货' ([int](Sql "SELECT stock FROM dish WHERE id=$newId") -eq 50) '库存 30+20=50'

$r = Post-Form $ac "/admin/dishes/$newId/delete" @{ '_csrf' = $atok }
Check '删除菜品' ([int](Sql "SELECT COUNT(*) FROM dish WHERE id=$newId") -eq 0) '已删除'

Write-Host "`n===== 9. 页面渲染检查 =====" -ForegroundColor Cyan
foreach ($p in @('/menu', '/cart', '/orders', '/me', '/orders/checkout')) {
    $pg = Get-Page $c $p
    Check "顾客页 $p 正常渲染" ($pg.Status -eq 200) "状态 $($pg.Status)"
}
foreach ($p in @('/admin', '/admin/dishes', '/admin/categories', '/admin/orders', '/admin/reviews', '/admin/dishes/new', '/admin/dishes/1/edit')) {
    $pg = Get-Page $ac $p
    Check "后台页 $p 正常渲染" ($pg.Status -eq 200) "状态 $($pg.Status)"
}

Write-Host "`n===== 汇总 =====" -ForegroundColor Cyan
$pass = ($results | Where-Object Result -eq 'PASS').Count
$fail = ($results | Where-Object Result -eq 'FAIL').Count
Write-Host ("通过 {0} 项 / 失败 {1} 项" -f $pass, $fail) -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
$results | Where-Object Result -eq 'FAIL' | Format-Table -AutoSize

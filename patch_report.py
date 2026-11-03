# -*- coding: utf-8 -*-
"""修补 build_report_docx.py：
1. 架构图改用等宽对齐的画法（纯 ASCII + 全角框线，保证右边界对齐）
2. 封面信息表真正隐藏边框
"""
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

P = r"C:\Users\34519\spring-tool-suite-3.9.4.RELEASE-e4.7.3a-win32-x86_64\campus-takeout\build_report_docx.py"
src = open(P, encoding="utf-8").read()

# ---------- 1. 替换架构图 ----------
start = src.index('add_code_block(doc,\n    "┌──')
end = src.index('add_heading(doc, "3.3 功能模块说明", 2)')

# 架构图：每层一个框，框内文字左对齐 + 右侧补空格到固定宽度
# 用全角空格保证视觉宽度一致（Consolas 与宋体混排时，全角字符占 2 个半角宽度）
def box(title, lines, width=46):
    pad = lambda s: s + " " * max(0, width - 2 - len(s))
    out = ["┌" + "─" * width + "┐",
           "│ " + pad(title) + "│"]
    for ln in lines:
        out.append("│ " + pad(ln) + "│")
    out.append("└" + "─" * width + "┘")
    return out

diagram = []
diagram += box("浏览器（Thymeleaf 服务端渲染页面）", [])
diagram += ["                    │ HTTP（CSRF 保护）"]
diagram += box("Spring Security 过滤器链",
               ["认证：AppUserDetailsService → 数据库",
                "授权：/admin/** 需 ROLE_ADMIN",
                "密码加密：BCryptPasswordEncoder"])
diagram += ["                    │"]
diagram += box("Controller 层（请求处理）",
               ["MenuController    菜单浏览、搜索、详情",
                "CartController    购物车操作",
                "OrderController   下单、支付、取消、评价",
                "AuthController    登录、注册、个人中心",
                "AdminController   后台管理",
                "GlobalExceptionHandler  统一异常处理"])
diagram += ["                    │"]
diagram += box("Service 层（业务规则与事务）",
               ["DishService    菜品/分类业务",
                "CartService    购物车（合并、校验库存）",
                "OrderService   下单、支付、状态流转、统计",
                "UserService    注册、资料、密码、充值",
                "ReviewService  评价业务"])
diagram += ["                    │"]
diagram += box("Repository 层（Spring Data JPA）",
               ["UserRepository      CategoryRepository",
                "DishRepository      CartItemRepository",
                "OrderRepository     ReviewRepository"])
diagram += ["                    │"]
diagram += box("MySQL 8.0 数据库（7 张表）",
               ["app_user  category  dish  cart_item",
                "orders  order_item  review"])

diagram_text = "\n".join(diagram)
# 转成 Python 源码中的字符串字面量
literal = "\n".join('    "%s\\n"' % ln.replace("\\", "\\\\").replace('"', '\\"')
                    for ln in diagram_text.split("\n"))

new_block = 'add_code_block(doc,\n' + literal + ')\n\n'
src = src[:start] + new_block + src[end:]

# ---------- 2. 封面包框真正隐藏：给表格设置 tblBorders 为 nil ----------
old_border = '''# 隐藏信息表的边框
for row in info_table.rows:
    for cell in row.cells:
        tcpr = cell._tc.get_or_add_tcPr()
        borders = OxmlElement("w:tcBorders")
        for edge in ("top", "left", "bottom", "right"):
            el = OxmlElement(f"w:{edge}")
            el.set(qn("w:val"), "nil")
            borders.append(el)
        tcpr.append(borders)'''

new_border = '''# 隐藏信息表的边框（表格级 + 单元格级都要设置）
def remove_table_borders(table):
    tbl = table._tbl
    tblPr = tbl.tblPr
    borders = OxmlElement("w:tblBorders")
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        el = OxmlElement(f"w:{edge}")
        el.set(qn("w:val"), "nil")
        el.set(qn("w:sz"), "0")
        el.set(qn("w:space"), "0")
        el.set(qn("w:color"), "auto")
        borders.append(el)
    existing = tblPr.find(qn("w:tblBorders"))
    if existing is not None:
        tblPr.remove(existing)
    tblPr.append(borders)
    for row in table.rows:
        for cell in row.cells:
            tcpr = cell._tc.get_or_add_tcPr()
            cb = OxmlElement("w:tcBorders")
            for edge in ("top", "left", "bottom", "right"):
                el = OxmlElement(f"w:{edge}")
                el.set(qn("w:val"), "nil")
                cb.append(el)
            tcpr.append(cb)

remove_table_borders(info_table)'''

if old_border not in src:
    raise SystemExit("未找到封面包框代码段")
src = src.replace(old_border, new_border)

# ---------- 3. Consolas 缺失告警：改用通用等宽字体 Courier New ----------
src = src.replace('MONO = "Consolas"', 'MONO = "Courier New"')

open(P, "w", encoding="utf-8").write(src)
print("脚本已修补")

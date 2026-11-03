# -*- coding: utf-8 -*-
"""把架构图从"文本画框"改为"表格布局"，彻底解决中英文混排导致的方框错位。

同时修复封面信息表边框。
"""
import io
import re
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

P = r"C:\Users\34519\spring-tool-suite-3.9.4.RELEASE-e4.7.3a-win32-x86_64\campus-takeout\build_report_docx.py"
src = open(P, encoding="utf-8").read()

# ---------- 1. 新增 add_arch_diagram 函数（插到 add_code_block 之后） ----------
anchor = 'def add_bullet(doc, text, marker="·"):'
if anchor not in src:
    raise SystemExit("找不到插入锚点")

arch_func = '''def add_box_row(table, text, bold=False, shaded=False, indent_cm=0.0, font_size=10):
    """在单列表格中写一行带底色的"层""""
    cell = table.add_row().cells[0]
    if shaded:
        shade_cell(cell, "FFFFFF")
    cell.text = ""
    p = cell.paragraphs[0]
    set_para_format(p, 1.15, 3, 3, None, WD_ALIGN_PARAGRAPH.CENTER)
    if indent_cm:
        p.paragraph_format.left_indent = Cm(indent_cm)
        p.alignment = WD_ALIGN_PARAGRAPH.LEFT
    run = p.add_run(text)
    set_run_font(run, HEI if bold else SONG, font_size, bold)


def add_arch_diagram(doc):
    """用表格画架构图：每层一个单元格，层与层之间插入箭头行"""
    layers = [
        ("浏览器（Thymeleaf 服务端渲染页面）", []),
        ("Spring Security 过滤器链", [
            "认证：AppUserDetailsService → 数据库",
            "授权：/admin/** 需 ROLE_ADMIN",
            "密码加密：BCryptPasswordEncoder",
        ]),
        ("Controller 层（请求处理）", [
            "MenuController   菜单浏览、搜索、详情",
            "CartController   购物车操作",
            "OrderController  下单、支付、取消、评价",
            "AuthController   登录、注册、个人中心",
            "AdminController  后台管理",
            "GlobalExceptionHandler  统一异常处理",
        ]),
        ("Service 层（业务规则与事务）", [
            "DishService   菜品/分类业务",
            "CartService   购物车（合并、校验库存）",
            "OrderService  下单、支付、状态流转、统计",
            "UserService   注册、资料、密码、充值",
            "ReviewService 评价业务",
        ]),
        ("Repository 层（Spring Data JPA）", [
            "UserRepository    CategoryRepository",
            "DishRepository    CartItemRepository",
            "OrderRepository   ReviewRepository",
        ]),
        ("MySQL 8.0 数据库（7 张表）", [
            "app_user   category   dish   cart_item",
            "orders   order_item   review",
        ]),
    ]
    arrows = ["                ↓ HTTP", "                ↓", "                ↓",
              "                ↓", "                ↓"]

    table = doc.add_table(rows=0, cols=1)
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.style = "Table Grid"

    for idx, (title, sublines) in enumerate(layers):
        cell = table.add_row().cells[0]
        cell.text = ""
        # 标题行
        p = cell.paragraphs[0]
        set_para_format(p, 1.2, 4, 2, None, WD_ALIGN_PARAGRAPH.CENTER)
        run = p.add_run(title)
        set_run_font(run, HEI, 10.5, True)
        # 子内容
        for ln in sublines:
            sp = cell.add_paragraph()
            set_para_format(sp, 1.15, 0, 1, None, WD_ALIGN_PARAGRAPH.LEFT)
            sp.paragraph_format.left_indent = Cm(0.5)
            r = sp.add_run(ln)
            set_run_font(r, SONG, 9.5)
        # 统一底色
        shade_cell(cell, "F7F9FC")

        if idx < len(arrows):
            ac = table.add_row().cells[0]
            ac.text = ""
            ap = ac.paragraphs[0]
            set_para_format(ap, 1.0, 1, 1, None, WD_ALIGN_PARAGRAPH.CENTER)
            ar = ap.add_run(arrows[idx])
            set_run_font(ar, HEI, 9.5, True, (0x44, 0x44, 0x44))
            # 箭头行无边框
            tcpr = ac._tc.get_or_add_tcPr()
            cb = OxmlElement("w:tcBorders")
            for edge in ("top", "left", "bottom", "right"):
                el = OxmlElement(f"w:{edge}")
                el.set(qn("w:val"), "nil")
                cb.append(el)
            tcpr.append(cb)

    # 表格总宽固定
    for row in table.rows:
        row.cells[0].width = Cm(13.5)
    doc.add_paragraph().paragraph_format.space_after = Pt(2)


'''

src = src.replace(anchor, arch_func + anchor, 1)

# ---------- 2. 替换架构图调用为表格版本 ----------
start = src.index('add_code_block(doc,\n    "┌')
# 找到该 add_code_block 调用的结束位置：下一个 add_heading
end = src.index('add_heading(doc, "3.3 功能模块说明", 2)')
src = src[:start] + "add_arch_diagram(doc)\n\n" + src[end:]

# ---------- 3. 封面表格：移除表格样式 + 双重去边框 ----------
old = 'remove_table_borders(info_table)'
new = '''info_table.style = None
remove_table_borders(info_table)'''
src = src.replace(old, new)

open(P, "w", encoding="utf-8").write(src)
print("已改为表格版架构图")

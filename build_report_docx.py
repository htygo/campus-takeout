# -*- coding: utf-8 -*-
"""根据 REPORT.md 生成课程实验报告 Word 文档"""
import os
from docx import Document
from docx.shared import Pt, Cm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.section import WD_SECTION
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

PROJ = r"C:\Users\34519\spring-tool-suite-3.9.4.RELEASE-e4.7.3a-win32-x86_64\campus-takeout"
SHOTS = os.path.join(PROJ, "screenshots")
OUT = os.path.join(PROJ, "课程实验报告-校园外卖点餐系统.docx")

SONG = "宋体"
HEI = "黑体"
KAI = "楷体"
MONO = "Courier New"


# ---------------- 底层工具 ----------------
def set_run_font(run, name=SONG, size=12, bold=False, color=None):
    run.font.name = name
    run.font.size = Pt(size)
    run.font.bold = bold
    if color:
        run.font.color.rgb = RGBColor(*color)
    # 中文字体必须显式设置 eastAsia
    rpr = run._element.get_or_add_rPr()
    rfonts = rpr.find(qn("w:rFonts"))
    if rfonts is None:
        rfonts = OxmlElement("w:rFonts")
        rpr.append(rfonts)
    rfonts.set(qn("w:eastAsia"), name)
    rfonts.set(qn("w:ascii"), name)
    rfonts.set(qn("w:hAnsi"), name)


def set_para_format(p, line_spacing=1.5, space_before=0, space_after=0,
                    first_indent=None, align=WD_ALIGN_PARAGRAPH.JUSTIFY):
    pf = p.paragraph_format
    pf.line_spacing = line_spacing
    pf.space_before = Pt(space_before)
    pf.space_after = Pt(space_after)
    if first_indent is not None:
        pf.first_line_indent = Cm(first_indent)
    p.alignment = align


def add_body_paragraph(doc, text, size=12, indent=True, bold=False, align=None):
    p = doc.add_paragraph()
    set_para_format(p, 1.5, 0, 0, 0.74 if indent else None,
                    align if align is not None else WD_ALIGN_PARAGRAPH.JUSTIFY)
    run = p.add_run(text)
    set_run_font(run, SONG, size, bold)
    return p


def add_heading(doc, text, level):
    """自定义标题：黑体，层级字重递减"""
    p = doc.add_paragraph()
    if level == 1:
        set_para_format(p, 1.5, 12, 6, None, WD_ALIGN_PARAGRAPH.LEFT)
        size = 16
    elif level == 2:
        set_para_format(p, 1.5, 10, 4, None, WD_ALIGN_PARAGRAPH.LEFT)
        size = 14
    else:
        set_para_format(p, 1.5, 6, 3, None, WD_ALIGN_PARAGRAPH.LEFT)
        size = 12.5
    run = p.add_run(text)
    set_run_font(run, HEI, size, True)
    # 设置大纲级别，使 Word 导航窗格目录可用
    ppr = p._element.get_or_add_pPr()
    outline = OxmlElement("w:outlineLvl")
    outline.set(qn("w:val"), str(level - 1))
    ppr.append(outline)
    # 标题与下段同页
    keep = OxmlElement("w:keepNext")
    ppr.append(keep)
    return p


def shade_cell(cell, hex_color):
    tcpr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), hex_color)
    tcpr.append(shd)


def add_table(doc, headers, rows, widths=None, font_size=10.5):
    table = doc.add_table(rows=1, cols=len(headers))
    table.style = "Table Grid"
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    hdr = table.rows[0].cells
    for i, h in enumerate(headers):
        hdr[i].text = ""
        p = hdr[i].paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        set_para_format(p, 1.15, 2, 2)
        run = p.add_run(h)
        set_run_font(run, HEI, font_size, True)
        shade_cell(hdr[i], "E8E8E8")

    for row in rows:
        cells = table.add_row().cells
        for i, val in enumerate(row):
            cells[i].text = ""
            p = cells[i].paragraphs[0]
            set_para_format(p, 1.15, 2, 2, None, WD_ALIGN_PARAGRAPH.LEFT)
            run = p.add_run(str(val))
            set_run_font(run, SONG, font_size, False)

    if widths:
        for row in table.rows:
            for i, w in enumerate(widths):
                row.cells[i].width = Cm(w)
    # 表后留白
    doc.add_paragraph().paragraph_format.space_after = Pt(2)
    return table


def add_code_block(doc, code):
    """代码块：等宽字体 + 灰色底纹 + 细边框"""
    table = doc.add_table(rows=1, cols=1)
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    cell = table.rows[0].cells[0]
    shade_cell(cell, "F5F5F5")
    # 边框
    tcpr = cell._tc.get_or_add_tcPr()
    borders = OxmlElement("w:tcBorders")
    for edge in ("top", "left", "bottom", "right"):
        el = OxmlElement(f"w:{edge}")
        el.set(qn("w:val"), "single")
        el.set(qn("w:sz"), "4")
        el.set(qn("w:color"), "BFBFBF")
        borders.append(el)
    tcpr.append(borders)

    cell.text = ""
    lines = code.split("\n")
    for i, line in enumerate(lines):
        p = cell.paragraphs[0] if i == 0 else cell.add_paragraph()
        set_para_format(p, 1.0, 0, 0, None, WD_ALIGN_PARAGRAPH.LEFT)
        run = p.add_run(line if line else " ")
        set_run_font(run, MONO, 9.5)
        run._element.rPr.rFonts.set(qn("w:eastAsia"), SONG)
    doc.add_paragraph().paragraph_format.space_after = Pt(2)


def add_box_row(table, text, bold=False, shaded=False, indent_cm=0.0, font_size=10):
    """在单列表格中写入一行带底色的层级标题"""
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


def add_bullet(doc, text, marker="·"):
    p = doc.add_paragraph()
    set_para_format(p, 1.5, 0, 0, None, WD_ALIGN_PARAGRAPH.JUSTIFY)
    p.paragraph_format.left_indent = Cm(0.74)
    p.paragraph_format.first_line_indent = Cm(-0.37)
    run = p.add_run(f"{marker} {text}")
    set_run_font(run, SONG, 12)
    return p


def add_image(doc, filename, caption, width_cm=15.0):
    path = os.path.join(SHOTS, filename)
    if not os.path.exists(path):
        add_body_paragraph(doc, f"[缺少截图：{filename}]")
        return
    p = doc.add_paragraph()
    set_para_format(p, 1.0, 6, 2, None, WD_ALIGN_PARAGRAPH.CENTER)
    p.add_run().add_picture(path, width=Cm(width_cm))
    cap = doc.add_paragraph()
    set_para_format(cap, 1.0, 0, 10, None, WD_ALIGN_PARAGRAPH.CENTER)
    run = cap.add_run(caption)
    set_run_font(run, KAI, 10.5)


def add_page_number_footer(section):
    footer = section.footer
    p = footer.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run()
    fld1 = OxmlElement("w:fldChar"); fld1.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText"); instr.set(qn("xml:space"), "preserve"); instr.text = "PAGE"
    fld2 = OxmlElement("w:fldChar"); fld2.set(qn("w:fldCharType"), "end")
    run._r.append(fld1); run._r.append(instr); run._r.append(fld2)
    set_run_font(run, SONG, 10.5)


def set_east_asian_doc_defaults(doc):
    """设置文档默认中文字体，避免样式里残留下默认的西文字体"""
    style = doc.styles["Normal"]
    style.font.name = SONG
    style.font.size = Pt(12)
    style.element.rPr.rFonts.set(qn("w:eastAsia"), SONG)


# ---------------- 开始构建 ----------------
doc = Document()
set_east_asian_doc_defaults(doc)

sec = doc.sections[0]
sec.page_width = Cm(21)
sec.page_height = Cm(29.7)
sec.top_margin = Cm(2.54)
sec.bottom_margin = Cm(2.54)
sec.left_margin = Cm(3.0)
sec.right_margin = Cm(2.6)
add_page_number_footer(sec)

# ============ 封面 ============
for _ in range(4):
    doc.add_paragraph()

p = doc.add_paragraph()
set_para_format(p, 1.5, 0, 20, None, WD_ALIGN_PARAGRAPH.CENTER)
run = p.add_run("Spring Boot 课程实验报告")
set_run_font(run, HEI, 26, True)

p = doc.add_paragraph()
set_para_format(p, 1.5, 0, 60, None, WD_ALIGN_PARAGRAPH.CENTER)
run = p.add_run("校园外卖点餐系统")
set_run_font(run, HEI, 22, True)

p = doc.add_paragraph()
set_para_format(p, 1.5, 0, 40, None, WD_ALIGN_PARAGRAPH.CENTER)
run = p.add_run("—— 模仿网上书店系统实现的同类业务系统 ——")
set_run_font(run, KAI, 13)

for _ in range(3):
    doc.add_paragraph()

info = [
    ("姓　　名", ""),
    ("学　　号", ""),
    ("班　　级", ""),
    ("专　　业", ""),
    ("指导教师", ""),
    ("提交日期", ""),
]
info_table = doc.add_table(rows=len(info), cols=2)
info_table.alignment = WD_TABLE_ALIGNMENT.CENTER
for i, (k, v) in enumerate(info):
    c0, c1 = info_table.rows[i].cells
    c0.width = Cm(3.5)
    c1.width = Cm(6.5)
    p0 = c0.paragraphs[0]
    set_para_format(p0, 1.5, 4, 4, None, WD_ALIGN_PARAGRAPH.CENTER)
    r0 = p0.add_run(k + "：")
    set_run_font(r0, HEI, 13, True)
    p1 = c1.paragraphs[0]
    set_para_format(p1, 1.5, 4, 4, None, WD_ALIGN_PARAGRAPH.CENTER)
    r1 = p1.add_run("________________")
    set_run_font(r1, SONG, 13)

# 隐藏信息表的边框（表格级 + 单元格级都要设置）
def remove_table_borders(table):
    tbl = table._tbl
    tblPr = tbl.tblPr
    borders = OxmlElement("w:tblBorders")
    # 用白色细线（而非 nil）：Word 与 LibreOffice 都稳定渲染成"无线"
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        el = OxmlElement(f"w:{edge}")
        el.set(qn("w:val"), "single")
        el.set(qn("w:sz"), "2")
        el.set(qn("w:space"), "0")
        el.set(qn("w:color"), "FFFFFF")
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
                el.set(qn("w:val"), "single")
                el.set(qn("w:sz"), "2")
                el.set(qn("w:color"), "FFFFFF")
                cb.append(el)
            tcpr.append(cb)

info_table.style = None
remove_table_borders(info_table)

doc.add_page_break()

# ============ 一、个人信息及学习体会 ============
add_heading(doc, "一、个人信息及学习体会", 1)

add_heading(doc, "1.1 个人信息", 2)
add_table(doc,
          ["项目", "内容"],
          [["姓名", ""], ["学号", ""], ["班级", ""], ["专业", ""], ["完成时间", ""]],
          widths=[4, 9])

add_heading(doc, "1.2 学习体会", 2)

add_body_paragraph(doc,
    "本次大作业参照课堂上讲解的「网上书店系统」，独立完成了一个同类业务系统——校园外卖点餐系统。"
    "整个过程下来，收获主要集中在以下几个方面：")

add_body_paragraph(doc,
    "第一，真正理解了分层架构的意义。以前写代码习惯把所有逻辑堆在一个类里，这次按照 "
    "Controller → Service → Repository 三层来组织，才体会到分层的价值：Controller 只负责接收请求和选择视图，"
    "Service 承载业务规则和事务边界，Repository 只管数据访问。当需要加「取消订单要退款」这种规则时，"
    "只需改 OrderService 一个方法，不用到处找代码。")

add_body_paragraph(doc,
    "第二，理解了事务和并发的实际含义。课堂上讲 @Transactional 时觉得就是个注解，"
    "直到自己实现「支付」才明白其中分量：支付这一个动作要同时完成「扣库存、扣余额、改订单状态」三件事，"
    "任何一步失败都必须整体回滚。为了验证这一点，我专门写了一个测试：把某菜品库存手动改成 0 再支付，"
    "确认余额没有被扣、订单仍停留在待支付状态，才算真正放心。")

add_body_paragraph(doc,
    "第三，意识到了「超卖」这个经典问题。最初我写的是「先查询库存，再判断够不够，最后更新」，"
    "后来发现并发时两个请求可能都读到「还有 1 份」，结果卖出两份。最终改成数据库层面带条件的原子更新，"
    "通过判断影响行数是否为 0 来确认扣减是否成功，从根源上解决了这个问题。具体写法见 2.2 节。")

add_body_paragraph(doc,
    "第四，对 Spring Security 有了完整的实践认识。从「为什么表单提交报 403」开始，"
    "查资料才明白 CSRF 防护的机制，学会了在表单中带 token；也学会了用 ROLE_USER / ROLE_ADMIN 区分权限，"
    "用 sec:authorize 控制页面上按钮的显示与隐藏。")

add_body_paragraph(doc,
    "第五，认识到「能跑」和「好用」之间还有很大距离。功能写完后，逐个页面截图检查，"
    "才发现有些 emoji 在 Windows 字体下显示成方框，一些金额没做格式化显示成 22.0 而不是 22.00。"
    "这些细节很影响观感，也让我养成了「交付前自己完整走一遍」的习惯。")

add_body_paragraph(doc, "遇到的问题与解决方式：", indent=True, bold=True)
add_table(doc,
          ["问题现象", "原因分析", "解决方式"],
          [
              ["提交表单报 403", "Spring Security 默认开启 CSRF 防护", "表单中携带 _csrf token"],
              ["错误提示页返回 500", "Thymeleaf 不支持 ?:（Elvis）运算符", "改写为三元表达式"],
              ["同一菜品不同口味被合并", "查询条件没考虑口味字段", "用 (user_id, dish_id, taste) 唯一索引 + 专门查询"],
              ["中文保存到数据库乱码", "连接串未指定字符集", "JDBC URL 加 characterEncoding=utf8，库用 utf8mb4"],
          ],
          widths=[4.2, 5.2, 5.6])

# ============ 二、自己增加的功能和特色 ============
add_heading(doc, "二、自己增加的功能和特色", 1)

add_body_paragraph(doc,
    "在满足「Spring Boot + MySQL」基本要求之外，本系统在课堂示例基础上增加了以下功能和技术特色。")

add_heading(doc, "2.1 功能扩展", 2)
add_table(doc,
          ["序号", "功能", "说明", "课堂示例中是否有"],
          [
              ["1", "用户注册", "顾客可自主注册，密码 BCrypt 加密", "无"],
              ["2", "菜品分类管理", "分类增删改 + 排序号", "无"],
              ["3", "关键字搜索", "按菜名/描述模糊搜索", "无"],
              ["4", "口味规格", "同一菜品多口味，购物车按口味分行", "无"],
              ["5", "库存与销量", "库存实时扣减，销量累加，售罄自动置灰", "无"],
              ["6", "订单体系", "独立订单表 + 明细表，生成唯一订单号", "无"],
              ["7", "订单状态机", "待支付 → 已支付 → 配送中 → 已完成 / 已取消", "无"],
              ["8", "余额充值与支付", "个人中心充值，下单用余额支付", "部分（仅扣款）"],
              ["9", "订单评价", "1–5 星评分 + 文字，每单限评一次", "无"],
              ["10", "经营数据看板", "营业额、销售额、订单数、状态分布", "无"],
              ["11", "管理员订单处理", "接单、配送、完成、取消并退款", "无"],
              ["12", "菜品补货", "一键增加库存", "无"],
              ["13", "个人中心", "改资料、改密码、充值", "无"],
              ["14", "统一错误页", "业务异常友好提示，不出现白页", "无"],
          ],
          widths=[1.3, 3.4, 6.8, 3.0])

add_heading(doc, "2.2 技术特色", 2)

add_body_paragraph(doc, "（1）防超卖：数据库层面的原子条件更新", indent=False, bold=True)
add_body_paragraph(doc,
    "使用带条件的 UPDATE 语句配合影响行数判断，在数据库层面保证库存不会被扣成负数：")
add_code_block(doc,
    "UPDATE dish SET stock = stock - :qty, sales = sales + :qty\n"
    "WHERE id = :id AND stock >= :qty")
add_body_paragraph(doc,
    "影响行数为 0 即说明库存不足，Service 层抛出业务异常，整个支付事务回滚。"
    "相比「先查再减」的写法，从根本上避免了并发下的超卖问题。")

add_body_paragraph(doc, "（2）事务原子性", indent=False, bold=True)
add_body_paragraph(doc,
    "支付操作把「扣库存 + 扣余额 + 改状态」放在同一个 @Transactional 事务中，"
    "任一环节抛异常则全部回滚。已通过自动化测试验证：库存不足时余额不变、订单状态保持不变。")

add_body_paragraph(doc, "（3）订单明细快照", indent=False, bold=True)
add_body_paragraph(doc,
    "下单时把菜名和单价复制进 order_item 表，商家后续改价、改名都不影响历史订单，"
    "这是电商系统的标准做法。")

add_body_paragraph(doc, "（4）余额与库存双向一致", indent=False, bold=True)
add_body_paragraph(doc,
    "管理员取消已支付订单时，自动退还余额并回补库存，保证账实相符。")

add_body_paragraph(doc, "（5）金额使用 BigDecimal", indent=False, bold=True)
add_body_paragraph(doc,
    "全程使用 BigDecimal 而非 float，避免浮点精度误差（课堂示例中用的是 float）。")

add_body_paragraph(doc, "（6）安全加固", indent=False, bold=True)
add_bullet(doc, "密码 BCrypt 加盐哈希，数据库不存明文")
add_bullet(doc, "启用 CSRF 防护，所有写操作校验 token")
add_bullet(doc, "越权防护：查看/操作订单时校验归属，顾客无法访问他人数据")
add_bullet(doc, "接口级权限控制：/admin/** 仅管理员可访问，顾客访问返回 403")

add_body_paragraph(doc, "（7）界面设计", indent=False, bold=True)
add_body_paragraph(doc,
    "无图片资源依赖（用 emoji 做菜品图），纯 CSS 实现，风格统一、响应式布局。")

# ============ 三、系统架构及功能模块 ============
add_heading(doc, "三、系统架构及功能模块", 1)

add_heading(doc, "3.1 技术架构", 2)
add_table(doc,
          ["层次", "技术选型", "说明"],
          [
              ["表现层", "Thymeleaf 3.1 + 原生 CSS", "服务端渲染，无需前端构建工具"],
              ["控制层", "Spring MVC", "请求路由、参数绑定、视图选择"],
              ["业务层", "Spring Service + @Transactional", "业务规则、事务边界"],
              ["持久层", "Spring Data JPA (Hibernate 6)", "方法名派生查询 + JPQL"],
              ["数据库", "MySQL 8.0", "InnoDB 引擎，支持事务"],
              ["安全", "Spring Security 6.5", "认证、授权、CSRF、密码加密"],
          ],
          widths=[2.6, 5.6, 6.3])
add_body_paragraph(doc,
    "运行环境：JDK 17、Maven 3.9、内嵌 Tomcat 10、Spring Boot 3.5.16。")

add_heading(doc, "3.2 系统架构图", 2)
add_body_paragraph(doc,
    "系统采用经典的分层架构，自上而下依次为表现层、安全过滤层、控制层、业务层、持久层和数据库：")
add_arch_diagram(doc)

add_heading(doc, "3.3 功能模块说明", 2)

add_body_paragraph(doc, "（1）顾客端", indent=False, bold=True)
add_bullet(doc, "菜单首页：展示全部上架菜品，顶部为「人气爆款」（按销量取前 4），支持分类筛选与关键字搜索。售罄菜品按钮置灰，未登录用户显示「登录后下单」。")
add_bullet(doc, "菜品详情：展示描述、价格、库存、销量、可选口味，以及该菜品的顾客评价。")
add_bullet(doc, "购物车：同菜品同口味自动合并数量；可改数量、删除、清空；实时显示合计金额。")
add_bullet(doc, "结算下单：填写收货地址、电话、备注，系统把购物车内容转为订单并清空购物车。")
add_bullet(doc, "支付：使用余额支付，成功后扣库存、扣余额、改状态；余额不足会提示。")
add_bullet(doc, "订单管理：订单列表 + 详情页状态进度条（提交 → 支付 → 配送 → 完成），可取消待支付订单。")
add_bullet(doc, "评价：已完成的订单可打 1–5 星并留言，每单仅一次。")
add_bullet(doc, "个人中心：修改昵称/手机/地址、修改密码、余额充值。")

add_body_paragraph(doc, "（2）管理端", indent=False, bold=True)
add_bullet(doc, "数据看板：营业额、累计销售额、订单总数、在售菜品数，以及各状态订单数量、最近订单。")
add_bullet(doc, "菜品管理：列表、新增、编辑、上下架切换、补货、删除；库存 ≤10 会标红提醒。")
add_bullet(doc, "分类管理：新增、行内编辑（名称 + 排序号）、删除（分类下有菜品时禁止删除）。")
add_bullet(doc, "订单处理：按状态筛选；「已支付 → 配送中 → 已完成」推进；取消订单自动退款并回补库存。")
add_bullet(doc, "顾客评价：查看最新评价与评分。")

add_heading(doc, "3.4 核心业务流程：下单与支付", 2)
add_code_block(doc,
    "顾客            系统                          数据库\n"
    " │ 加入购物车 → 校验库存、同口味合并      → INSERT/UPDATE cart_item\n"
    " │ 提交订单  → 生成订单号、明细快照、清空购物车 → INSERT orders, order_item\n"
    " │ 点击支付  → 校验归属、状态、余额\n"
    " │            → 原子扣库存（WHERE stock >= qty）\n"
    " │            → 扣减余额\n"
    " │            → 状态改为 PAID             → UPDATE orders, app_user, dish\n"
    " │            ← 任一步失败则整体回滚\n"
    " │ 商家接单  → 状态流转 PAID→DELIVERING→COMPLETED\n"
    " │ 顾客评价  → 校验已完成、未评价过        → INSERT review")

# ============ 四、数据库表的设计 ============
add_heading(doc, "四、数据库表的设计", 1)

add_body_paragraph(doc,
    "数据库名：campus_takeout，字符集 utf8mb4，存储引擎 InnoDB，共 7 张表。")

add_heading(doc, "4.1 E-R 关系说明", 2)
add_code_block(doc,
    "app_user 1 ──── n cart_item n ──── 1 dish\n"
    "app_user 1 ──── n orders   1 ──── n order_item\n"
    "category 1 ──── n dish\n"
    "orders   1 ──── 1 review")
add_bullet(doc, "一个用户可以有多条购物车记录、多个订单")
add_bullet(doc, "一个订单包含多条订单明细")
add_bullet(doc, "一个分类下有多个菜品")
add_bullet(doc, "一个订单对应最多一条评价")

add_heading(doc, "4.2 表结构详细设计", 2)

add_body_paragraph(doc, "表 1：app_user（用户表）", indent=False, bold=True)
add_table(doc, ["字段", "类型", "约束", "说明"], [
    ["id", "BIGINT", "PK, AUTO_INCREMENT", "主键"],
    ["username", "VARCHAR(50)", "NOT NULL, UNIQUE", "登录用户名"],
    ["password", "VARCHAR(100)", "NOT NULL", "BCrypt 加密后的密码"],
    ["nickname", "VARCHAR(50)", "", "昵称"],
    ["phone", "VARCHAR(20)", "", "手机号"],
    ["address", "VARCHAR(255)", "", "默认收货地址"],
    ["balance", "DECIMAL(10,2)", "NOT NULL, 默认 0", "账户余额"],
    ["role", "VARCHAR(20)", "NOT NULL", "USER / ADMIN"],
    ["enabled", "TINYINT(1)", "NOT NULL, 默认 1", "是否启用"],
    ["created_at", "DATETIME", "NOT NULL", "注册时间"],
], widths=[3.0, 3.2, 4.4, 4.4])

add_body_paragraph(doc, "表 2：category（分类表）", indent=False, bold=True)
add_table(doc, ["字段", "类型", "约束", "说明"], [
    ["id", "BIGINT", "PK", "主键"],
    ["name", "VARCHAR(50)", "NOT NULL, UNIQUE", "分类名"],
    ["sort_order", "INT", "NOT NULL, 默认 0", "排序号"],
], widths=[3.0, 3.2, 4.4, 4.4])

add_body_paragraph(doc, "表 3：dish（菜品表）", indent=False, bold=True)
add_table(doc, ["字段", "类型", "约束", "说明"], [
    ["id", "BIGINT", "PK", "主键"],
    ["name", "VARCHAR(100)", "NOT NULL", "菜品名"],
    ["category_id", "BIGINT", "NOT NULL, FK → category.id", "所属分类"],
    ["price", "DECIMAL(10,2)", "NOT NULL", "单价"],
    ["stock", "INT", "NOT NULL, 默认 0", "库存"],
    ["sales", "INT", "NOT NULL, 默认 0", "累计销量"],
    ["description", "VARCHAR(500)", "", "描述"],
    ["taste", "VARCHAR(100)", "", "口味选项（逗号分隔）"],
    ["image_emoji", "VARCHAR(16)", "", "图片占位符"],
    ["on_sale", "TINYINT(1)", "NOT NULL, 默认 1", "是否上架"],
    ["created_at", "DATETIME", "NOT NULL", "创建时间"],
], widths=[3.0, 3.2, 4.4, 4.4])

add_body_paragraph(doc, "表 4：cart_item（购物车表）", indent=False, bold=True)
add_table(doc, ["字段", "类型", "约束", "说明"], [
    ["id", "BIGINT", "PK", "主键"],
    ["user_id", "BIGINT", "NOT NULL, FK → app_user.id", "所属用户"],
    ["dish_id", "BIGINT", "NOT NULL, FK → dish.id", "菜品"],
    ["quantity", "INT", "NOT NULL, 默认 1", "数量"],
    ["taste", "VARCHAR(50)", "", "选择的口味"],
], widths=[3.0, 3.2, 4.4, 4.4])
add_body_paragraph(doc,
    "唯一索引 uk_cart_user_dish_taste (user_id, dish_id, taste)：保证同一用户同一菜品的同一口味只有一条记录，"
    "从而支持合并数量。")

add_body_paragraph(doc, "表 5：orders（订单表）", indent=False, bold=True)
add_table(doc, ["字段", "类型", "约束", "说明"], [
    ["id", "BIGINT", "PK", "主键"],
    ["order_no", "VARCHAR(32)", "NOT NULL, UNIQUE", "订单号"],
    ["user_id", "BIGINT", "NOT NULL, FK → app_user.id", "下单用户"],
    ["total_amount", "DECIMAL(10,2)", "NOT NULL", "订单总额"],
    ["status", "VARCHAR(20)", "NOT NULL", "订单状态"],
    ["address", "VARCHAR(255)", "NOT NULL", "收货地址"],
    ["phone", "VARCHAR(20)", "NOT NULL", "联系电话"],
    ["remark", "VARCHAR(255)", "", "备注"],
    ["created_at", "DATETIME", "NOT NULL", "下单时间"],
    ["paid_at", "DATETIME", "", "支付时间"],
    ["completed_at", "DATETIME", "", "完成时间"],
], widths=[3.0, 3.2, 4.4, 4.4])
add_body_paragraph(doc,
    "订单状态枚举：CREATED（待支付）、PAID（已支付）、DELIVERING（配送中）、COMPLETED（已完成）、CANCELLED（已取消）。")

add_body_paragraph(doc, "表 6：order_item（订单明细表）", indent=False, bold=True)
add_table(doc, ["字段", "类型", "约束", "说明"], [
    ["id", "BIGINT", "PK", "主键"],
    ["order_id", "BIGINT", "NOT NULL, FK → orders.id", "所属订单"],
    ["dish_id", "BIGINT", "NOT NULL", "菜品 ID"],
    ["dish_name", "VARCHAR(100)", "NOT NULL", "菜名快照"],
    ["unit_price", "DECIMAL(10,2)", "NOT NULL", "单价快照"],
    ["quantity", "INT", "NOT NULL", "数量"],
    ["taste", "VARCHAR(50)", "", "口味"],
], widths=[3.0, 3.2, 4.4, 4.4])
add_body_paragraph(doc,
    "这里刻意冗余保存菜名和单价，是为了让历史订单不受后续改价影响。")

add_body_paragraph(doc, "表 7：review（评价表）", indent=False, bold=True)
add_table(doc, ["字段", "类型", "约束", "说明"], [
    ["id", "BIGINT", "PK", "主键"],
    ["order_id", "BIGINT", "NOT NULL, UNIQUE, FK → orders.id", "订单（唯一，每单只能评一次）"],
    ["user_id", "BIGINT", "NOT NULL", "评价人"],
    ["rating", "INT", "NOT NULL", "评分 1–5"],
    ["content", "VARCHAR(500)", "", "评价内容"],
    ["created_at", "DATETIME", "NOT NULL", "评价时间"],
], widths=[3.0, 3.2, 4.4, 4.4])

add_heading(doc, "4.3 设计要点说明", 2)
add_bullet(doc, "顾客与管理员共用一张用户表，通过 role 字段区分，避免重复建表。")
add_bullet(doc, "金额统一使用 DECIMAL(10,2)，对应 Java 的 BigDecimal，杜绝浮点误差。")
add_bullet(doc, "订单明细做快照，符合电商系统的通用设计原则。")
add_bullet(doc, "唯一索引保证业务规则：购物车同口味合并、每单只评一次，都在数据库层面兜底。")
add_bullet(doc, "外键约束 + 级联删除：删除订单时自动删除其明细与评价，保证数据一致。")

# ============ 五、系统界面截图 ============
add_heading(doc, "五、系统界面截图", 1)

add_heading(doc, "5.1 顾客端", 2)

add_body_paragraph(doc, "（1）菜单首页（游客视角）", indent=False, bold=True)
add_image(doc, "01-menu-guest.png", "图 5-1  菜单首页：人气爆款推荐 + 分类筛选 + 菜品网格")
add_body_paragraph(doc,
    "说明：顶部为人气爆款推荐，中间为分类筛选，下方为菜品卡片网格。未登录时按钮显示「登录后下单」。")

add_body_paragraph(doc, "（2）登录页面", indent=False, bold=True)
add_image(doc, "02-login.png", "图 5-2  登录页面", width_cm=11)
add_body_paragraph(doc, "说明：提供演示账号提示，便于测试。")

add_body_paragraph(doc, "（3）注册页面", indent=False, bold=True)
add_image(doc, "04-register.png", "图 5-3  注册页面", width_cm=11)

add_body_paragraph(doc, "（4）菜品详情", indent=False, bold=True)
add_image(doc, "03-dish-detail.png", "图 5-4  菜品详情：可选口味 + 库存销量 + 顾客评价")
add_body_paragraph(doc, "说明：展示菜品信息、可选口味、库存销量和顾客评价。")

add_body_paragraph(doc, "（5）购物车", indent=False, bold=True)
add_image(doc, "05-cart.png", "图 5-5  购物车：同菜品不同口味分行显示，实时计算合计")
add_body_paragraph(doc, "说明：同一菜品不同口味分两行显示，底部实时计算合计金额。")

add_body_paragraph(doc, "（6）确认订单（结算页）", indent=False, bold=True)
add_image(doc, "06-checkout.png", "图 5-6  确认订单页：填写收货信息 + 商品清单 + 金额汇总")

add_body_paragraph(doc, "（7）我的订单", indent=False, bold=True)
add_image(doc, "07-orders.png", "图 5-7  我的订单列表")

add_body_paragraph(doc, "（8）订单详情", indent=False, bold=True)
add_image(doc, "09-order-detail.png", "图 5-8  订单详情：顶部状态进度条显示订单流转位置", width_cm=12)
add_body_paragraph(doc, "说明：顶部为状态进度条，展示订单流转到哪一步。")

add_body_paragraph(doc, "（9）个人中心", indent=False, bold=True)
add_image(doc, "08-profile.png", "图 5-9  个人中心：余额充值、资料修改、密码修改", width_cm=12)

add_heading(doc, "5.2 管理端", 2)

add_body_paragraph(doc, "（10）数据看板", indent=False, bold=True)
add_image(doc, "10-admin-dashboard.png", "图 5-10  管理后台数据看板")
add_body_paragraph(doc, "说明：展示营业额、销售额、订单数、各状态订单数量及最近订单。")

add_body_paragraph(doc, "（11）菜品管理", indent=False, bold=True)
add_image(doc, "11-admin-dishes.png", "图 5-11  菜品管理：增删改、上下架、补货")

add_body_paragraph(doc, "（12）订单处理", indent=False, bold=True)
add_image(doc, "12-admin-orders.png", "图 5-12  订单处理：按状态筛选、推进状态、取消退款")

add_body_paragraph(doc, "（13）分类管理", indent=False, bold=True)
add_image(doc, "13-admin-categories.png", "图 5-13  分类管理")

add_body_paragraph(doc, "（14）菜品编辑表单", indent=False, bold=True)
add_image(doc, "14-admin-dish-form.png", "图 5-14  菜品新增/编辑表单", width_cm=12)

add_body_paragraph(doc, "（15）顾客评价", indent=False, bold=True)
add_image(doc, "15-admin-reviews.png", "图 5-15  顾客评价查看")

# ============ 六、测试记录 ============
add_heading(doc, "六、测试记录", 1)
add_body_paragraph(doc,
    "系统开发完成后进行了自动化功能测试，覆盖主要业务流程，共 70 项断言全部通过。")
add_table(doc, ["测试类别", "项数", "覆盖内容"], [
    ["登录与认证", "3", "正确登录、错误密码、管理员登录"],
    ["菜单浏览", "7", "游客访问、菜品展示、分类筛选、搜索、下架隐藏、详情页"],
    ["权限隔离", "3", "游客被拦截、顾客访问后台 403、管理员正常访问"],
    ["购物车", "6", "加入、合并、分口味、下架拦截、超库存拦截、清空"],
    ["下单流程", "10", "结算页、订单生成、单号、金额、明细快照、购物车清空"],
    ["支付与库存", "7", "支付成功、库存扣减、销量累加、余额扣减、重复支付拦截"],
    ["订单流转", "5", "后台筛选、状态推进、完成时间、非法流转拦截"],
    ["评价", "3", "提交评价、入库、重复评价拦截"],
    ["事务回滚", "3", "库存不足支付失败、余额不变、订单状态不变"],
    ["余额校验", "1", "余额不足无法支付"],
    ["取消退款", "4", "取消订单、库存回补、余额退款、状态变更"],
    ["菜品管理", "6", "新增、前台可见、下架、前台隐藏、补货、删除"],
    ["页面渲染", "12", "全部前后台页面返回 200"],
], widths=[3.2, 1.6, 10.2])

# ============ 七、总结 ============
add_heading(doc, "七、总结", 1)
add_body_paragraph(doc,
    "本项目以网上书店系统为原型，完整实现了一个校园外卖点餐系统，涵盖用户、菜单、购物车、"
    "订单、支付、评价、统计等完整业务闭环。")
add_body_paragraph(doc,
    "技术上采用 Spring Boot 3.5 + Spring Data JPA + MySQL 8 + Spring Security + Thymeleaf，"
    "做到了分层清晰、事务安全、防止超卖、权限隔离。")
add_body_paragraph(doc,
    "最大的体会是：业务系统的难点不在于把功能写出来，而在于把边界情况处理对——"
    "库存不足怎么办、重复支付怎么拦、取消订单库存和钱怎么退回去，"
    "这些才是一个系统真正「能用」的关键。")

doc.save(OUT)
print("已生成:", OUT)
print("大小:", round(os.path.getsize(OUT) / 1024, 1), "KB")

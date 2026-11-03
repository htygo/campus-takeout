# 🍱 校园外卖点餐系统（campus-takeout）

> Spring Boot + MySQL 课程大作业 —— 模仿「网上书店系统」实现的一个同类业务系统。

## 一、项目简介

本项目以课堂上讲解的「网上书店系统」为参照，实现了**校园外卖点餐系统**。
两者在业务骨架上一一对应（浏览商品 → 加入购物车 → 下单 → 支付 → 结账 → 评价），
但外卖场景额外增加了**库存并发控制、订单状态机、余额充值、口味规格、营业统计**等能力。

## 二、技术栈

| 层次 | 技术 | 版本 |
|---|---|---|
| 语言 | Java | 17 |
| 框架 | Spring Boot | 3.5.16 |
| 持久层 | Spring Data JPA (Hibernate) | 6.6 |
| 数据库 | MySQL | 8.0 |
| 安全 | Spring Security（BCrypt + 角色权限 + CSRF） | 6.5 |
| 模板引擎 | Thymeleaf | 3.1 |
| 构建 | Maven | 3.9 |
| 前端 | 原生 HTML/CSS（无框架依赖） | — |

## 三、快速启动

### 1. 准备数据库

```bash
# 先建表
mysql -u root -p < sql/schema.sql
# 再导入初始数据
mysql -u root -p < sql/data.sql
```

或者用 MySQL Workbench / Navicat 打开这两个脚本依次执行。

### 2. 修改数据库配置

编辑 `src/main/resources/application.yml`，把用户名密码改成你自己的：

```yaml
spring:
  datasource:
    username: root
    password: 123456   # ← 改成你的 MySQL 密码
```

### 3. 启动

```bash
# 方式一：Maven 直接运行
mvn spring-boot:run

# 方式二：打包后运行
mvn clean package -DskipTests
java -jar target/campus-takeout-1.0.0.jar
```

浏览器打开 <http://localhost:8080>

### 4. 演示账号

| 角色 | 用户名 | 密码 | 说明 |
|---|---|---|---|
| 管理员 | `admin` | `admin123` | 可进入管理后台 |
| 顾客 | `student` | `123456` | 余额 200 元，含历史订单 |
| 顾客 | `tom` | `123456` | 余额 150 元 |

## 四、功能模块

### 顾客端

| 功能 | 说明 |
|---|---|
| 菜单浏览 | 首页展示全部上架菜品，含人气爆款推荐 |
| 分类筛选 | 按盖浇饭 / 面食 / 小吃 / 饮品分类查看 |
| 关键字搜索 | 按菜名或描述模糊搜索 |
| 菜品详情 | 查看描述、口味、库存、销量、顾客评价 |
| 购物车 | 加入、改数量、删除、清空；同菜品同口味自动合并 |
| 结算下单 | 填收货地址、电话、备注，生成订单 |
| 支付 | 使用账户余额支付，余额不足会提示 |
| 订单管理 | 查看全部订单、跟踪状态进度、取消待支付订单 |
| 评价 | 对已完成订单打分（1–5 星）并留言，每单限评一次 |
| 个人中心 | 修改资料、修改密码、余额充值 |

### 管理端（`/admin`）

| 功能 | 说明 |
|---|---|
| 数据看板 | 营业额、销售额、订单数、各状态订单数量 |
| 菜品管理 | 新增、编辑、上架/下架、补货、删除 |
| 分类管理 | 新增、修改、排序、删除（有菜品时禁止删除） |
| 订单处理 | 按状态筛选，推进「已支付 → 配送中 → 已完成」，取消并退款 |
| 顾客评价 | 查看最新评价 |

## 五、系统架构

```
┌──────────────────────────────────────────────┐
│  浏览器（Thymeleaf 服务端渲染页面）           │
└───────────────────┬──────────────────────────┘
                    │ HTTP（CSRF 保护）
┌───────────────────▼──────────────────────────┐
│  Security 过滤器链                            │
│  ├─ 认证：AppUserDetailsService → DB          │
│  ├─ 授权：/admin/** → ROLE_ADMIN              │
│  └─ 密码加密：BCryptPasswordEncoder           │
├──────────────────────────────────────────────┤
│  Controller 层                                │
│  MenuController / CartController /            │
│  OrderController / AuthController /           │
│  AdminController                              │
│  └─ GlobalExceptionHandler（统一错误页）      │
├──────────────────────────────────────────────┤
│  Service 层（业务规则、事务边界）              │
│  DishService / CartService / OrderService /   │
│  UserService / ReviewService                  │
├──────────────────────────────────────────────┤
│  Repository 层（Spring Data JPA）             │
├──────────────────────────────────────────────┤
│  MySQL 8.0（7 张表，InnoDB 事务）              │
└──────────────────────────────────────────────┘
```

## 六、数据库设计（7 张表）

| 表名 | 说明 | 关键字段 |
|---|---|---|
| `app_user` | 用户（顾客 + 管理员） | `username` 唯一，`role` 区分角色，`balance` 余额，密码 BCrypt |
| `category` | 餐品分类 | `name` 唯一，`sort_order` 排序 |
| `dish` | 餐品 | `category_id` 外键，`price`/`stock`/`sales`，`taste` 口味，`on_sale` 上下架 |
| `cart_item` | 购物车 | `(user_id, dish_id, taste)` 唯一，保证同口味合并 |
| `orders` | 订单 | `order_no` 唯一，`status` 状态机，`user_id` 归属 |
| `order_item` | 订单明细 | **菜名与单价快照**，历史订单不受改价影响 |
| `review` | 评价 | `order_id` 唯一（每单限评一次），`rating` 1–5 |

完整建表语句见 [`sql/schema.sql`](sql/schema.sql)。

## 七、项目亮点（报告「自己增加的功能和特色」可写）

1. **防超卖：带条件的原子库存扣减**
   ```sql
   UPDATE dish SET stock = stock - :qty, sales = sales + :qty
   WHERE id = :id AND stock >= :qty
   ```
   影响行数为 0 即判定库存不足并抛出业务异常，整个支付事务回滚。
   相比「先查再减」的写法，从根本上避免了并发下的超卖。

2. **订单状态机**：`CREATED → PAID → DELIVERING → COMPLETED`，
   非法流转（如重复支付、已完成再推进）会被服务层拦截。

3. **事务原子性**：支付动作「扣库存 + 扣余额 + 改状态」在同一事务内，
   任一环节失败全部回滚（已通过自动化测试验证：库存不足时余额不变、订单仍为待支付）。

4. **取消订单自动退款 + 回补库存**，金额与库存双向一致。

5. **数据快照设计**：订单明细保存下单时的菜名与单价，
   商家后续调整价格或改名，历史订单仍保持原样。

6. **密码安全**：BCrypt 加盐哈希存储，数据库中不存明文；
   同时启用 CSRF 防护，所有写操作都校验 token。

7. **越权防护**：查看订单、操作购物车时校验归属，
   顾客无法访问他人订单或管理后台（已测试 403）。

8. **金额使用 `BigDecimal`**（而非 `float`），避免浮点精度问题。

## 八、目录结构

```
campus-takeout/
├── pom.xml
├── README.md
├── REPORT.md                    # 课程实验报告（可直接改用）
├── sql/
│   ├── schema.sql               # 建库建表
│   └── data.sql                 # 初始数据
├── screenshots/                 # 系统界面截图
└── src/main/
    ├── java/com/example/takeout/
    │   ├── CampusTakeoutApplication.java
    │   ├── config/SecurityConfig.java
    │   ├── controller/          # 4 个 Controller + 全局异常处理
    │   ├── entity/              # 7 个实体 + 2 个枚举
    │   ├── exception/
    │   ├── repository/          # 6 个 Repository
    │   ├── security/            # 登录认证、当前用户
    │   └── service/             # 5 个 Service
    └── resources/
        ├── application.yml
        ├── static/css/app.css
        └── templates/           # Thymeleaf 页面
            ├── fragments/layout.html
            ├── admin/           # 后台页面
            └── *.html           # 前台页面
```

## 九、常见问题

**Q：启动报 `Table 'campus_takeout.xxx' doesn't exist`？**
A：没有执行 `sql/schema.sql`。项目配置了 `ddl-auto: validate`，只校验不改表。

**Q：启动报 `Access denied for user 'root'`？**
A：`application.yml` 里的数据库密码不对，改成你自己的。

**Q：端口 8080 被占用？**
A：改 `application.yml` 中的 `server.port`，或用 `java -jar xxx.jar --server.port=8081`。

**Q：中文显示成乱码？**
A：确认数据库是 `utf8mb4`，导入脚本时加 `--default-character-set=utf8mb4`。

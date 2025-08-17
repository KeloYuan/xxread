# 小元读书 - 后端开发文档

## 项目概览

小元读书是一款优雅的Flutter电子书阅读器，具备用户系统、云端同步、社区功能等特性。本文档详细说明了后端系统的架构设计、API接口、数据库设计和实现指南。

## 技术栈推荐

### 后端框架
- **Node.js + Express** (推荐)
- **Python + FastAPI** (可选)
- **Java + Spring Boot** (可选)
- **Go + Gin** (可选)

### 数据库
- **主数据库**: PostgreSQL 或 MongoDB
- **缓存**: Redis
- **文件存储**: AWS S3 / 阿里云OSS / 腾讯云COS

### 其他服务
- **消息队列**: Redis / RabbitMQ
- **搜索引擎**: Elasticsearch (社区搜索功能)
- **实时通信**: Socket.IO (社区聊天)

## 系统架构

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Flutter App   │    │   Web Admin     │    │   Third Party   │
│     (移动端)     │    │    (管理后台)    │    │     Services    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │   API Gateway   │
                    │   (负载均衡)     │
                    └─────────────────┘
                                 │
         ┌───────────────────────┼───────────────────────┐
         │                       │                       │
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   User Service  │    │   Book Service  │    │ Community Svc   │
│    (用户服务)    │    │   (图书服务)    │    │   (社区服务)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │    Database     │
                    │   (PostgreSQL)  │
                    └─────────────────┘
```

## 数据库设计

### 用户相关表

#### users (用户表)
```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    display_name VARCHAR(100),
    avatar_url TEXT,
    bio TEXT,
    is_verified BOOLEAN DEFAULT false,
    subscription_type VARCHAR(20) DEFAULT 'free', -- free, premium, pro
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login_at TIMESTAMP,
    is_active BOOLEAN DEFAULT true
);
```

#### user_profiles (用户配置表)
```sql
CREATE TABLE user_profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    reading_preferences JSONB, -- 阅读偏好设置
    privacy_settings JSONB,    -- 隐私设置
    notification_settings JSONB, -- 通知设置
    theme_settings JSONB,      -- 主题设置
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### 图书相关表

#### books (图书表)
```sql
CREATE TABLE books (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(255) NOT NULL,
    author VARCHAR(255),
    description TEXT,
    isbn VARCHAR(20),
    language VARCHAR(10) DEFAULT 'zh',
    category_id UUID REFERENCES categories(id),
    cover_url TEXT,
    file_size BIGINT,
    page_count INTEGER,
    word_count INTEGER,
    format VARCHAR(10) NOT NULL, -- txt, epub, pdf
    is_public BOOLEAN DEFAULT false,
    upload_user_id UUID REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

#### user_books (用户图书关联表)
```sql
CREATE TABLE user_books (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    book_id UUID NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    file_path TEXT NOT NULL, -- 云端文件路径
    current_page INTEGER DEFAULT 0,
    total_pages INTEGER DEFAULT 1,
    reading_progress DECIMAL(5,4) DEFAULT 0.0000,
    last_read_at TIMESTAMP,
    is_favorite BOOLEAN DEFAULT false,
    tags TEXT[], -- 用户自定义标签
    notes JSONB, -- 笔记数据
    bookmarks JSONB, -- 书签数据
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, book_id)
);
```

#### categories (分类表)
```sql
CREATE TABLE categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    parent_id UUID REFERENCES categories(id),
    sort_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### 阅读统计表

#### reading_sessions (阅读会话表)
```sql
CREATE TABLE reading_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    book_id UUID NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP,
    duration_seconds INTEGER,
    pages_read INTEGER DEFAULT 0,
    start_page INTEGER,
    end_page INTEGER,
    device_info JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

#### reading_stats (阅读统计表)
```sql
CREATE TABLE reading_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    total_duration_seconds INTEGER DEFAULT 0,
    books_read INTEGER DEFAULT 0,
    pages_read INTEGER DEFAULT 0,
    session_count INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, date)
);
```

### 社区相关表

#### posts (帖子表)
```sql
CREATE TABLE posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    type VARCHAR(20) DEFAULT 'discussion', -- discussion, review, question
    book_id UUID REFERENCES books(id), -- 关联图书(可选)
    images TEXT[], -- 图片URLs
    tags TEXT[],
    like_count INTEGER DEFAULT 0,
    comment_count INTEGER DEFAULT 0,
    view_count INTEGER DEFAULT 0,
    is_pinned BOOLEAN DEFAULT false,
    is_deleted BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

#### comments (评论表)
```sql
CREATE TABLE comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES comments(id), -- 回复评论
    content TEXT NOT NULL,
    like_count INTEGER DEFAULT 0,
    is_deleted BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

#### follows (关注关系表)
```sql
CREATE TABLE follows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    follower_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    following_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(follower_id, following_id)
);
```

## API接口设计

### 认证相关接口

#### POST /api/auth/register
用户注册
```json
{
    "username": "string",
    "email": "string",
    "password": "string",
    "display_name": "string"
}
```

#### POST /api/auth/login
用户登录
```json
{
    "email": "string",
    "password": "string"
}
```

#### POST /api/auth/refresh
刷新Token
```json
{
    "refresh_token": "string"
}
```

#### POST /api/auth/logout
用户登出

### 用户相关接口

#### GET /api/user/profile
获取用户资料

#### PUT /api/user/profile
更新用户资料
```json
{
    "display_name": "string",
    "bio": "string",
    "avatar_url": "string"
}
```

#### GET /api/user/settings
获取用户设置

#### PUT /api/user/settings
更新用户设置
```json
{
    "reading_preferences": {
        "font_size": 18,
        "line_spacing": 1.5,
        "theme": "light"
    },
    "privacy_settings": {
        "show_reading_stats": true
    }
}
```

### 图书相关接口

#### GET /api/books
获取图书列表
- Query参数: page, limit, category, search, sort

#### GET /api/books/:id
获取图书详情

#### POST /api/books/upload
上传图书文件

#### GET /api/user/books
获取用户图书库
- Query参数: page, limit, sort, filter

#### POST /api/user/books
添加图书到用户库
```json
{
    "book_id": "uuid",
    "file_url": "string"
}
```

#### PUT /api/user/books/:id/progress
更新阅读进度
```json
{
    "current_page": 10,
    "total_pages": 100,
    "reading_progress": 0.1,
    "last_read_at": "2024-01-01T00:00:00Z"
}
```

#### POST /api/user/books/:id/bookmark
添加书签
```json
{
    "page": 50,
    "note": "重要段落",
    "position": "paragraph_3"
}
```

#### GET /api/user/books/:id/bookmarks
获取书签列表

### 阅读统计接口

#### POST /api/reading/session/start
开始阅读会话
```json
{
    "book_id": "uuid",
    "start_page": 10
}
```

#### POST /api/reading/session/end
结束阅读会话
```json
{
    "session_id": "uuid",
    "end_page": 15,
    "duration_seconds": 1200
}
```

#### GET /api/reading/stats
获取阅读统计
- Query参数: period (daily, weekly, monthly, yearly)

#### GET /api/reading/stats/summary
获取统计摘要

### 社区相关接口

#### GET /api/community/posts
获取社区帖子列表
- Query参数: page, limit, type, sort, tag

#### POST /api/community/posts
发布帖子
```json
{
    "title": "string",
    "content": "string",
    "type": "discussion",
    "book_id": "uuid",
    "tags": ["标签1", "标签2"]
}
```

#### GET /api/community/posts/:id
获取帖子详情

#### POST /api/community/posts/:id/like
点赞帖子

#### POST /api/community/posts/:id/comments
发表评论
```json
{
    "content": "string",
    "parent_id": "uuid"  // 可选，回复评论
}
```

#### GET /api/community/posts/:id/comments
获取帖子评论列表

#### POST /api/community/follow
关注用户
```json
{
    "user_id": "uuid"
}
```

#### GET /api/community/following
获取关注列表

#### GET /api/community/followers
获取粉丝列表

## 文件存储方案

### 图书文件存储
1. **上传流程**:
   - 用户选择文件上传
   - 生成唯一文件名 (UUID + 原扩展名)
   - 上传到云存储服务
   - 返回文件URL和元信息

2. **存储路径规范**:
   ```
   /books/{user_id}/{book_id}/{filename}
   例: /books/123e4567-e89b-12d3-a456-426614174000/book.epub
   ```

3. **文件访问控制**:
   - 私有文件: 需要签名URL访问
   - 公共文件: 直接URL访问
   - CDN加速

### 用户头像存储
```
/avatars/{user_id}/{filename}
例: /avatars/123e4567-e89b-12d3-a456-426614174000/avatar.jpg
```

## 安全考虑

### 认证与授权
- JWT Token认证
- Refresh Token机制
- 角色基础访问控制 (RBAC)
- API访问频率限制

### 数据安全
- 密码加密 (bcrypt)
- 敏感数据加密
- SQL注入防护
- XSS防护
- HTTPS强制使用

### 文件安全
- 文件类型验证
- 文件大小限制
- 病毒扫描
- 访问权限控制

## 性能优化

### 数据库优化
- 索引优化
- 查询优化
- 分页查询
- 读写分离
- 数据库连接池

### 缓存策略
- Redis缓存热点数据
- CDN缓存静态资源
- 浏览器缓存
- 应用层缓存

### 并发处理
- 消息队列异步处理
- 数据库连接池
- 限流机制
- 负载均衡

## 部署方案

### 开发环境
```
Docker + Docker Compose
- API服务
- PostgreSQL
- Redis
- MinIO (本地对象存储)
```

### 生产环境
```
Kubernetes 或 Docker Swarm
- 多副本部署
- 自动扩缩容
- 健康检查
- 日志收集
- 监控告警
```

## 监控与日志

### 监控指标
- API响应时间
- 数据库查询性能
- 系统资源使用率
- 用户活跃度
- 错误率

### 日志管理
- 结构化日志
- 日志等级管理
- 日志收集 (ELK Stack)
- 日志分析

## 开发规范

### 代码规范
- 统一代码风格
- 注释规范
- 错误处理
- 单元测试
- 代码审查

### API设计规范
- RESTful设计
- 统一响应格式
- 错误码规范
- 版本管理
- 文档维护

### 数据库规范
- 命名规范
- 索引规范
- 迁移脚本
- 备份策略

## 实施步骤

### 阶段1: 基础功能 (4-6周)
1. 用户认证系统
2. 图书上传和存储
3. 基础阅读功能
4. 阅读进度同步

### 阶段2: 增强功能 (3-4周)
1. 阅读统计
2. 书签和笔记同步
3. 用户设置同步
4. 文件管理优化

### 阶段3: 社区功能 (6-8周)
1. 用户关注系统
2. 帖子和评论功能
3. 图书评价和推荐
4. 社区互动功能

### 阶段4: 高级功能 (4-6周)
1. 智能推荐
2. 全文搜索
3. 数据分析
4. 性能优化

## 成本估算

### 开发成本
- 后端开发: 3-4个月
- DevOps配置: 2-3周
- 测试和优化: 2-3周

### 运营成本 (月)
- 服务器: $200-500
- 数据库: $100-300
- 存储: $50-200
- CDN: $50-100
- 监控工具: $50-100

## 总结

本文档提供了小元读书后端系统的完整设计方案。建议按照阶段性实施，先完成核心功能，再逐步添加高级功能。在开发过程中，要特别注意数据安全、性能优化和用户体验。

如有技术问题或需要进一步讨论，请随时联系。
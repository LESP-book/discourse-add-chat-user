# discourse-add-chat-user
● 插件实现完成 ✅                                              
                                            
  discourse-add-chat-user 插件已创建完毕，以下是完整的实现总结：                                                    
                                                                                                                    
  ---                                                                                                               
  文件结构                                                                                                          
                                                                                                                    
  discourse-add-chat-user/
  ├── plugin.rb                  ← 主入口，包含所有 hook 逻辑
  ├── config/
  │   └── settings.yml           ← 站点设置（启用开关 + 监督用户名）
  └── README.md

  站点设置（管理后台可配置）

  ┌───────────────────────────────────┬─────────┬────────┬──────────────────┐
  │              设置项               │  类型   │ 默认值 │       说明       │
  ├───────────────────────────────────┼─────────┼────────┼──────────────────┤
  │ add_chat_user_enabled             │ boolean │ false  │ 插件总开关       │
  ├───────────────────────────────────┼─────────┼────────┼──────────────────┤
  │ add_chat_user_supervisor_username │ string  │ ""     │ 监督用户的用户名 │
  └───────────────────────────────────┴─────────┴────────┴──────────────────┘

  核心 Hook 架构（三层防护）

  Hook: Hook 1 CreateDmChannelExtension
  目标: Chat::CreateDirectMessageChannel#create_memberships
  触发时机: 用户创建新的 1v1 或群组 DM 时
  ────────────────────────────────────────
  Hook: Hook 2 AddUsersExtension
  目标: Chat::AddUsersToChannel#create_memberships
  触发时机: 向已有群组 DM 添加新成员时
  ────────────────────────────────────────
  Hook: Hook 3 ForUserIdsPatch
  目标: Chat::DirectMessage.for_user_ids
  触发时机: 查找已有 DM 频道时排除监督用户，防止重复创建

  关键设计决策

  1. prepend 模式：使用 Ruby prepend 重写 Service 方法，调用 super 保留原始逻辑后注入监督用户，安全且不破坏核心代码
  2. for_user_ids 补丁（最关键）：监督用户被添加到 direct_message_users 后，原始查询 ARRAY[A,B] =
  ARRAY_AGG(users.id) 会变成 [A,B] vs [A,B,Supervisor] 导致匹配失败。补丁使用 PostgreSQL FILTER (WHERE users.id !=
  ?) 子句在比较时排除监督用户，确保 DM 去重查询正常工作
  3. 幂等插入：使用 insert_all + unique_by 约束，重复调用不会报错

  部署方式

  将插件目录软链接或复制到 Discourse 的 plugins/ 目录下，重启应用后在管理后台启用并配置监督用户名即可。
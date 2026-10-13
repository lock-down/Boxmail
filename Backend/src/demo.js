import { saveAttachment } from './attachments.js';
export async function seedDemo(repo) {
  if (repo.get('meta', 'initialized')) return;
  repo.put('meta', { id: 'initialized' });
  repo.put('account', {
    id: 'demo',
    name: '张明远 · 演示账号',
    email: 'zhangmy@boxmail.example',
    username: '',
    imapHost: '',
    imapPort: 993,
    imapTLS: true,
    smtpHost: '',
    smtpPort: 465,
    smtpTLS: true,
    lastSync: null,
    isDemo: true,
  });
  const rows = [
    [
      '陈嘉禾',
      'chenjh@company.example',
      'Q3 产品路线图评审 · 会议纪要与排期确认',
      '各位好：\n\n昨天的 Q3 产品路线图评审会已顺利结束，感谢各位抽时间参与。现将会议结论与后续排期同步如下，请按照自己负责的模块逐条确认。\n\n三条主线的优先级与负责人已在会上达成一致：AI 助手能力由陈嘉禾负责，协作编辑由李思远负责，移动端重构由周雨桐负责。11 月中旬完成设计交付，12 月初进入灰度，Q4 末全量上线。\n\n预算为人民币 1,280,000 元。请于 10 月 31 日前确认 AI 助手模块设计排期，如对排期存在异议，请直接回复本邮件。\n\n祝好！\n陈嘉禾',
      '工作项目',
    ],
    [
      'Figma 产品动态',
      'news@figma.example',
      '本周新功能：AI 设计助手正式上线',
      '自动布局重构、变量批量替换，以及全新的 AI 设计助手现已向全部团队开放使用。查看产品公告了解详情。',
      '订阅资讯',
    ],
    [
      '财务部 · 王琳',
      'finance@company.example',
      '10 月差旅报销单据已审批通过',
      '报销金额 ¥4,860 已提交至财务付款队列，预计 3 个工作日内到账，请查收凭证。',
      '账单票据',
    ],
    [
      '李思远',
      'lisi@company.example',
      '关于品牌视觉升级的三个方案',
      '三套方案分别偏向稳健、锐利与温和方向，希望听听你更倾向哪一个整体气质。我们可以在本周四讨论。',
      '工作项目',
    ],
    [
      'AWS Billing',
      'billing@aws.example',
      'Your October invoice is available',
      'Your October invoice is ready. The amount due is $1,284.60. Please review the attached billing details.',
      '账单票据',
    ],
    [
      '周雨桐',
      'zhouyt@company.example',
      '下周三团队季度会时间安排',
      '已同步日历邀请，如时间冲突请在今天内告知，我来协调其他时段。会议地点：三楼会议室。',
      '工作项目',
    ],
  ];
  for (let i = 0; i < rows.length; i++) {
    const [sender, senderEmail, subject, body, category] = rows[i];
    const m = {
      id: `demo-${i}`,
      accountId: 'demo',
      folder: 'inbox',
      sender,
      senderEmail,
      to: 'zhangmy@boxmail.example',
      cc: '',
      subject,
      body,
      preview: body.replace(/\s+/g, ' ').slice(0, 110),
      date: new Date(Date.now() - i * 3600_000).toISOString(),
      unread: i < 4,
      starred: i === 0,
      category,
      attachmentIds: [],
      summary: null,
      messageId: `<demo-${i}@boxmail.example>`,
    };
    if (i === 0) {
      const a = await saveAttachment(
        repo,
        m.id,
        'Q3 路线图排期表.txt',
        Buffer.from(
          'Q3 产品路线图\nAI 助手：陈嘉禾，11 月中旬设计交付\n协作编辑：李思远，12 月初灰度\n移动端：周雨桐，Q4 末全量上线\n预算：1,280,000 元\n回执截止：10 月 31 日',
        ),
        'text/plain',
      );
      m.attachmentIds = [a.id];
      m.summary = {
        points: [
          '路线图共三条主线：AI 助手能力、协作编辑、移动端重构，分别由陈嘉禾、李思远、周雨桐负责。',
          '里程碑已锁定：11 月中旬完成设计交付，12 月初进入灰度，Q4 末全量上线。',
          '需要你的动作：确认 AI 助手能力模块的设计排期，并在 10 月 31 日前回执确认。',
        ],
        todos: [
          {
            id: 'demo-task-1',
            title: '回执确认 AI 助手模块设计排期',
            due: '10-31 截止',
            done: false,
          },
          {
            id: 'demo-task-2',
            title: '与李思远对齐协作方案优先级',
            due: '本周内',
            done: false,
          },
        ],
        keyInfo: [
          { label: '涉及预算', value: '¥1,280,000' },
          { label: '决策结论', value: '三条主线全部通过' },
        ],
      };
    }
    repo.put('message', m);
  }
  repo.put('draft', {
    id: 'demo-draft',
    accountId: 'demo',
    to: 'chenjh@company.example',
    cc: '',
    bcc: '',
    subject: 'Q3 产品路线图 · 排期确认',
    body: '陈经理，您好：\n\n感谢您在评审会上的详细反馈。我们已同步各模块负责人与关键里程碑，烦请您于本周五前回执确认。\n\n祝好！',
    attachmentIds: [],
    status: 'draft',
    updatedAt: new Date().toISOString(),
  });
}

import 'package:flutter/material.dart';

/// 分类 Schema 描述符
class CategorySchema {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final bool enterActionBoard;
  final List<SchemaField> fields;

  const CategorySchema({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.enterActionBoard,
    required this.fields,
  });

  Map<String, dynamic> toPromptSchema() {
    return {
      'category_id': id,
      'name': name,
      'description': description,
      'enter_action_board': enterActionBoard,
      'fields': {for (var f in fields) f.name: f.description},
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'color_hex': color.toARGB32().toRadixString(16),
      'enter_action_board': enterActionBoard,
      'fields': fields.map((e) => e.toJson()).toList(),
    };
  }

  factory CategorySchema.fromJson(Map<String, dynamic> json) {
    return CategorySchema(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      icon: Icons.category,
      color: json['color_hex'] != null 
          ? Color(int.parse(json['color_hex'] as String, radix: 16)) 
          : Colors.blueAccent,
      enterActionBoard: json['enter_action_board'] as bool? ?? false,
      fields: (json['fields'] as List<dynamic>?)
          ?.map((e) => SchemaField.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
    );
  }
}

class SchemaField {
  final String name;
  final String label;
  final String description;
  final String type; // "string", "number", "boolean", "date"

  const SchemaField({
    required this.name,
    required this.label,
    required this.description,
    this.type = "string",
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'label': label,
    'description': description,
    'type': type,
  };

  factory SchemaField.fromJson(Map<String, dynamic> json) => SchemaField(
    name: json['name'] as String,
    label: json['label'] as String? ?? json['name'] as String,
    description: json['description'] as String? ?? '',
    type: json['type'] as String? ?? 'string',
  );
}

/// 默认内置 5 大黄金分类
class DefaultCategories {
  static const voucher = CategorySchema(
    id: 'voucher',
    name: '瞬时凭证 / 取件码',
    description: '具有即时核销属性的凭证，如快递取件码、停车位拍照、核销码、电影票座次',
    icon: Icons.inventory_2_rounded,
    color: Color(0xFFF59E0B),
    enterActionBoard: true,
    fields: [
      SchemaField(name: 'code', label: '取件码/核销码', description: '清晰的提货码或验证码字符串，如 34-2-1088'),
      SchemaField(name: 'location', label: '驿站/柜机位置', description: '如“阳光花园南门菜鸟驿站”或“B2地下车库A区12号”'),
      SchemaField(name: 'provider', label: '平台/品牌', description: '如“中通快递”、“丰巢”、“瑞幸咖啡”'),
      SchemaField(name: 'expire_time', label: '有效期限', description: 'ISO 时间字符串或有效期限描述'),
    ],
  );

  static const schedule = CategorySchema(
    id: 'schedule',
    name: '日程与待办',
    description: '含有明确或隐含时间节点的事项安排、会议邀请、截止日期',
    icon: Icons.calendar_month_rounded,
    color: Color(0xFF3B82F6),
    enterActionBoard: true,
    fields: [
      SchemaField(name: 'event_title', label: '事项名称', description: '事项的核心标题'),
      SchemaField(name: 'start_time', label: '开始时间', description: '换算为准确的 ISO-8601 时间格式'),
      SchemaField(name: 'end_time', label: '结束时间', description: 'ISO-8601 时间格式或 null'),
      SchemaField(name: 'location', label: '地点', description: '线上会议链接或线下地点'),
      SchemaField(name: 'participants', label: '参与人', description: '提及的相关人物'),
      SchemaField(name: 'priority', label: '优先级', description: 'high / normal / low'),
    ],
  );

  static const bill = CategorySchema(
    id: 'bill',
    name: '账单与消费',
    description: '发票、转账截图、订单支付详情、收据',
    icon: Icons.receipt_long_rounded,
    color: Color(0xFF10B981),
    enterActionBoard: false,
    fields: [
      SchemaField(name: 'amount', label: '金额', description: '消费或支付的数值金额', type: 'number'),
      SchemaField(name: 'currency', label: '币种', description: 'CNY, USD 等'),
      SchemaField(name: 'merchant', label: '收款方/商户', description: '收款方或平台商家名称'),
      SchemaField(name: 'bill_type', label: '消费类型', description: '餐饮、交通、购物、转账等'),
      SchemaField(name: 'need_reimburse', label: '是否待报销', description: 'true 或 false', type: 'boolean'),
    ],
  );

  static const article = CategorySchema(
    id: 'article',
    name: '文章 / 攻略 / 稍后读',
    description: '公众号长文、小红书攻略、资讯干货、知乎回答截图',
    icon: Icons.menu_book_rounded,
    color: Color(0xFF8B5CF6),
    enterActionBoard: false,
    fields: [
      SchemaField(name: 'source_app', label: '来源平台', description: '小红书、微信公众号、知乎、微博等'),
      SchemaField(name: 'core_takeaways', label: '核心干货点', description: '最多3条提取出的干货要点'),
      SchemaField(name: 'entities', label: '提及实体', description: '提及的店名、地名、书名或工具名列表'),
      SchemaField(name: 'url', label: '链接', description: '若有原网址则提取'),
    ],
  );

  static const inspiration = CategorySchema(
    id: 'inspiration',
    name: '灵感与备忘',
    description: '碎片随笔、对话金句、临时草稿、通用灵感记录',
    icon: Icons.lightbulb_rounded,
    color: Color(0xFFEC4899),
    enterActionBoard: false,
    fields: [
      SchemaField(name: 'key_insight', label: '核心观点', description: '一句话凝练的核心见解'),
      SchemaField(name: 'context_summary', label: '背景提要', description: '对话或语境背景'),
      SchemaField(name: 'action_suggestion', label: '延伸行动建议', description: 'AI 为用户延伸出的下一步灵感建议'),
    ],
  );

  static List<CategorySchema> get all => [voucher, schedule, bill, article, inspiration];

  static CategorySchema findById(String id) {
    return all.firstWhere((e) => e.id == id, orElse: () => inspiration);
  }
}

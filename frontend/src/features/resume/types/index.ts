import { Process } from "@/types";
import React from "react";

/**
 * セクション名
 */
export type SectionName =
    | "basicInfo"
    | "career"
    | "project"
    | "certification"
    | "portfolio"
    | "socialLink"
    | "selfPromotion";

/**
 * セクション情報の定義
 */
export interface SectionInfo {
    key: SectionName;
    label: string; // 表示名
    type: "single" | "list"; // セクションタイプ(エントリーリストを表示するか否か)
    component: React.ComponentType; // 対応するコンポーネント
}

/**
 * 作業工程名
 */
export type ProcessName =
    | "要件定義"
    | "基本設計"
    | "詳細設計"
    | "実装・単体テスト"
    | "結合テスト"
    | "総合テスト"
    | "運用・保守";

/**
 * 作業工程バインド
 */
export type ProcessMap = Record<keyof Process, ProcessName>;

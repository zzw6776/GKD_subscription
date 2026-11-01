import { defineGkdApp } from '@gkd-kit/define';
import { OPEN_AD_ORDER } from '../globalGroups';

export default defineGkdApp({
  id: 'com.jjpengcheng.callshow.zjmc',
  name: '追剧喵',
  groups: [
    {
      key: 0,
      name: '开屏广告-跳过广告',
      desc: '跳过开屏广告和关闭插屏广告',
      enable: true,
      fastQuery: true,
      matchRoot: true,
      matchTime: 15000,
      forcedTime: 10000,
      actionCd: 1000,
      actionMaximum: 2,
      resetMatch: 'activity',
      order: OPEN_AD_ORDER,
      rules: [
        {
          key: 0,
          // skip_shade 是广告互动层，真实关闭逻辑绑定在 skip_ll。
          matches:
            '[vid="tobid_splash_skip_ll"][clickable=true][visibleToUser=true]',
          action: 'clickNode',
        },
        {
          key: 1,
          matches:
            '[vid="tobid_interstitial_skip_ll"][clickable=true][visibleToUser=true]',
          action: 'clickNode',
        },
      ],
    },
    {
      key: 1,
      name: '公告提示-关闭官方公告',
      desc: '点击“我知道了”关闭官方公告',
      enable: true,
      fastQuery: true,
      matchRoot: true,
      matchTime: 20000,
      forcedTime: 0,
      actionCd: 1000,
      actionMaximum: 1,
      resetMatch: 'app',
      order: OPEN_AD_ORDER + 1,
      rules: [
        {
          key: 0,
          matches:
            '[desc="APP官方公告"][visibleToUser=true] +n @[desc="我知道了"][clickable=true][visibleToUser=true]',
          action: 'clickNode',
        },
      ],
    },
    {
      key: 2,
      name: '开屏广告-倍孜插屏广告',
      desc: '关闭倍孜插屏广告，不限制进入页面后的匹配时间',
      enable: true,
      fastQuery: true,
      matchRoot: true,
      activityIds: ['com.beizi.ad.v2.activity.BeiZiNewInterstitialActivity'],
      actionCd: 1500,
      rules: [
        {
          key: 0,
          matches:
            '[vid="beizi_interstitial_ad_close_container_rl"][clickable=true][visibleToUser=true]',
          action: 'clickNode',
        },
      ],
    },
  ],
});

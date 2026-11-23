import { createApp } from 'vue';
import { createRouter, createWebHistory } from 'vue-router';
import App from './App.vue';
import { readConfig } from './api/client';
import IssueListView from './views/IssueListView.vue';
import { applyTheme } from './lib/theme';
import './styles.css';

const config = readConfig();
applyTheme();
const router = createRouter({
  history: createWebHistory(`${config.base}/`),
  routes: [
    { path: '/', redirect: '/issues' },
    { path: '/issues', name: 'issues', component: IssueListView },
    { path: '/:pathMatch(.*)*', redirect: '/issues' },
  ],
});
createApp(App).use(router).mount('#app');

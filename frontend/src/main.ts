import { createApp } from 'vue';
import { createRouter, createWebHistory } from 'vue-router';
import App from './App.vue';
import { readConfig } from './api/client';
import HomeView from './views/HomeView.vue';
import ContactListView from './views/ContactListView.vue';
import InvoiceListView from './views/InvoiceListView.vue';
import ProductListView from './views/ProductListView.vue';
import IssueListView from './views/IssueListView.vue';
import { applyTheme } from './lib/theme';
import { applyBrand } from './lib/brand';
import './tailwind.css';
import './styles.css';

const config = readConfig();
applyTheme();
applyBrand(config);
const router = createRouter({
  history: createWebHistory(`${config.base}/`),
  routes: [
    { path: '/', redirect: '/home' },
    { path: '/home', name: 'home', component: HomeView },
    { path: '/issues/:id(\\d+)?', name: 'issues', component: IssueListView },
    { path: '/contacts/:id(\\d+)?', name: 'contacts', component: ContactListView },
    { path: '/invoices/:id(\\d+)?', name: 'invoices', component: InvoiceListView },
    { path: '/products/:id(\\d+)?', name: 'products', component: ProductListView },
    { path: '/:pathMatch(.*)*', redirect: '/home' },
  ],
});
createApp(App).use(router).mount('#app');

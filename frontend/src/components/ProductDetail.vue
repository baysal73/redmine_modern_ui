<script setup lang="ts">
import { Package, Trash2 } from 'lucide-vue-next';
import { computed, ref, watch } from 'vue';
import { ApiError, api, readConfig } from '../api/client';
import { t } from '../i18n';
import { money } from '../lib/money';
import { toast } from '../lib/toast';
import { offerUndo } from '../lib/undo';
import type { ProductDetail, ProductOptions } from '../types';
import EditableField from './EditableField.vue';

const props = defineProps<{ id: number; opts: ProductOptions | null }>();
const emit = defineEmits<{ (e: 'close'): void; (e: 'changed'): void; (e: 'deleted'): void }>();
const config = readConfig();
const p = ref<ProductDetail | null>(null);
const loading = ref(false);
const error = ref('');

let seq = 0;
async function load(spinner = true) {
  const mine = ++seq;
  if (spinner) { loading.value = true; p.value = null; }
  error.value = '';
  try { const r = await api.product(props.id); if (mine === seq) p.value = r.product; }
  catch (e) { if (mine === seq) error.value = (e as ApiError).status === 404 ? t('pr.not_found') : (e as Error).message; }
  finally { if (mine === seq) loading.value = false; }
}
watch(() => props.id, () => load(), { immediate: true });

const ed = computed(() => !!p.value?.can_edit);
const classic = computed(() => `${config.root}/products/${props.id}`);
const sel = (l: { id: number; name: string }[] = []) => l.map((o) => ({ value: String(o.id), label: o.name }));
const num = (v: unknown) => String(v ?? '');

// One write path: undo restores the previous value of the changed field
async function patch(field: string, value: unknown) {
  const cur = p.value; if (!cur) return;
  const old: Record<string, unknown> = { status_id: cur.status.id, category_id: cur.category_id ?? '', tag_list: cur.tag_list.join(', '), price: cur.price ?? '' };
  const before = field in old ? old[field] : (cur as unknown as Record<string, unknown>)[field] ?? '';
  try {
    const r = await api.updateProduct(props.id, { [field]: value });
    p.value = r.product; emit('changed');
    offerUndo(t('edit.saved'), async () => { const b = await api.updateProduct(props.id, { [field]: before }); p.value = b.product; emit('changed'); });
  } catch (e) { toast(t('edit.failed', { message: (e as Error).message }), 'error'); await load(false); }
}

async function remove() {
  const cur = p.value; if (!cur || !window.confirm(t('pr.confirm_delete', { name: cur.name }))) return;
  try { await api.deleteProduct(props.id); toast(t('pr.deleted', { name: cur.name })); emit('deleted'); }
  catch (e) { toast((e as Error).message, 'error'); }
}
</script>

<template>
  <aside class="detail" aria-label="Product">
    <header class="detail-head">
      <button class="icon-btn" :aria-label="t('detail.close')" :title="t('detail.close') + ' (Esc)'" @click="emit('close')">✕</button>
      <span class="muted">{{ p?.code || '#' + id }}</span>
      <span class="spacer" />
      <button v-if="p?.can_delete && !p.used" class="icon-btn danger" :aria-label="t('delete')" :title="t('delete')" @click="remove"><Trash2 :size="15" /></button>
      <a :href="classic" class="muted small">{{ t('detail.classic') }}</a>
    </header>
    <p v-if="loading" class="muted pad">{{ t('detail.loading') }}</p>
    <p v-else-if="error" class="error" role="alert">{{ error }}</p>

    <div v-else-if="p" class="detail-body">
      <div class="ct-title">
        <img v-if="p.image_url" :src="p.image_url" alt="" class="ct-avatar" @error="($event.target as HTMLElement).style.display = 'none'">
        <Package v-else :size="36" class="text-muted" aria-hidden="true" />
        <div>
          <EditableField kind="text" :editable="ed" :label="t('pr.name')" :model-value="p.name" @save="(v) => patch('name', v)"><h2>{{ p.name }}</h2></EditableField>
          <p class="muted small">{{ p.project }}<template v-if="p.bundle"> · {{ t('pr.bundle') }}</template></p>
        </div>
      </div>

      <dl class="fields">
        <dt>{{ t('pr.code') }}</dt>
        <dd><EditableField kind="text" allow-empty :editable="ed" :label="t('pr.code')" :model-value="p.code" @save="(v) => patch('code', v)">{{ p.code || '—' }}</EditableField></dd>
        <dt>{{ t('pr.status') }}</dt>
        <dd><EditableField kind="select" :editable="ed" :label="t('pr.status')" :model-value="String(p.status.id)" :options="sel(opts?.statuses)" @save="(v) => patch('status_id', Number(v))"><span class="pill" :class="{ 'pill-closed': p.status.id === 2 }">{{ p.status.name }}</span></EditableField></dd>
        <dt>{{ t('pr.category') }}</dt>
        <dd><EditableField kind="select" allow-empty :editable="ed" :label="t('pr.category')" :model-value="num(p.category_id)" :options="sel(opts?.categories)" @save="(v) => patch('category_id', v === '' ? null : Number(v))">{{ p.category || '—' }}</EditableField></dd>
        <dt>{{ t('pr.price') }}</dt>
        <dd><EditableField kind="number" allow-empty :editable="ed" :label="t('pr.price')" :model-value="num(p.price)" @save="(v) => patch('price', v)">{{ p.price === null ? '—' : money(p.price, p.currency) }}</EditableField></dd>
        <dt>{{ t('pr.currency') }}</dt>
        <dd><EditableField kind="select" :editable="ed" :label="t('pr.currency')" :model-value="p.currency" :options="(opts?.currencies ?? [p.currency]).map((c) => ({ value: c, label: c }))" @save="(v) => patch('currency', v)">{{ p.currency }}</EditableField></dd>
        <dt>{{ t('pr.tags') }}</dt>
        <dd><EditableField kind="text" allow-empty :editable="ed" :label="t('pr.tags')" :model-value="p.tag_list.join(', ')" @save="(v) => patch('tag_list', v)">
          <span v-if="p.tag_list.length" class="tags"><span v-for="g in p.tag_list" :key="g" class="tag">{{ g }}</span></span><span v-else class="muted">—</span></EditableField></dd>
        <dt>{{ t('pr.description') }}</dt>
        <dd><EditableField kind="textarea" allow-empty :editable="ed" :label="t('pr.description')" :model-value="p.description" @save="(v) => patch('description', v)"><span v-if="p.description" class="pre">{{ p.description }}</span><span v-else class="muted">{{ ed ? t('pr.add_description') : '—' }}</span></EditableField></dd>
      </dl>

      <template v-if="p.bundle_items.length">
        <h3>{{ t('pr.bundle_items') }}</h3>
        <ul class="ct-list"><li v-for="i in p.bundle_items" :key="i.id"><a href="#" @click.prevent="$router.push('/products/' + i.id)">{{ i.name }}</a> <span class="muted">× {{ i.quantity }}</span></li></ul>
      </template>
      <p v-if="p.used && p.can_delete" class="muted small">{{ t('pr.used') }}</p>
      <p v-if="ed" class="muted small">{{ t('pr.readonly_hint') }}</p>
    </div>
  </aside>
</template>

<style>
.pre { white-space: pre-wrap; }
</style>

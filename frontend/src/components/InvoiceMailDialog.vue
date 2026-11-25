<script setup lang="ts">
import { Paperclip } from 'lucide-vue-next';
import { onMounted, ref } from 'vue';
import { api } from '../api/client';
import { t } from '../i18n';
import { toast } from '../lib/toast';
import type { InvoiceDetail } from '../types';

const props = defineProps<{ id: number; number: string }>();
const emit = defineEmits<{ (e: 'close'): void; (e: 'sent', invoice: InvoiceDetail): void }>();
const loading = ref(true);
const sending = ref(false);
const error = ref('');
const draft = ref(false);
const filename = ref('');
const f = ref({ to: '', cc: '', bcc: '', subject: '', message: '', mark_as_sent: true });
const showCc = ref(false);

onMounted(async () => {
  try {
    const d = await api.invoiceMail(props.id);
    f.value = { ...f.value, to: d.to, subject: d.subject, message: d.message };
    draft.value = d.draft; filename.value = d.filename;
  } catch (e) { error.value = (e as Error).message; }
  finally { loading.value = false; }
});
async function send() {
  if (sending.value || !f.value.to.trim()) return;
  sending.value = true; error.value = '';
  try {
    const r = await api.sendInvoiceMail(props.id, { ...f.value, mark_as_sent: draft.value && f.value.mark_as_sent ? '1' : '0' });
    toast(t('inv.mail.sent', { to: f.value.to })); emit('sent', r.invoice); emit('close');
  } catch (e) { error.value = (e as Error).message; }
  finally { sending.value = false; }
}
</script>

<template>
  <div class="overlay" @mousedown.self="emit('close')" @keydown.esc="emit('close')">
    <div class="dialog wide" role="dialog" aria-modal="true" aria-labelledby="im-title">
      <h2 id="im-title">{{ t('inv.mail.title', { number }) }}</h2>
      <p v-if="loading" class="muted">{{ t('loading') }}</p>
      <form v-else @submit.prevent="send">
        <label>{{ t('inv.mail.to') }}<input v-model="f.to" required type="text" autofocus :placeholder="'name@example.com'"></label>
        <button v-if="!showCc" type="button" class="link-btn" @click="showCc = true">{{ t('inv.mail.cc') }}</button>
        <div v-else class="row2">
          <label>CC<input v-model="f.cc"></label>
          <label>BCC<input v-model="f.bcc"></label>
        </div>
        <label>{{ t('inv.mail.subject') }}<input v-model="f.subject" required></label>
        <label>{{ t('inv.mail.message') }}<textarea v-model="f.message" rows="9" /></label>
        <p class="muted small flex items-center gap-1"><Paperclip :size="13" /> {{ filename }}</p>
        <label v-if="draft" class="check"><input v-model="f.mark_as_sent" type="checkbox"> {{ t('inv.mail.mark_sent') }}</label>
        <p v-if="error" class="error-text" role="alert">{{ error }}</p>
        <div class="dialog-actions">
          <button type="button" class="btn" @click="emit('close')">{{ t('create.cancel') }}</button>
          <button type="submit" class="btn primary" :disabled="sending || !f.to.trim() || !f.subject.trim()">{{ sending ? t('inv.mail.sending') : t('inv.mail.send') }}</button>
        </div>
      </form>
    </div>
  </div>
</template>

-- Private bucket for the document archive: no public URLs, 10 MB cap, PDF/JPG/PNG only.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'employee-documents',
  'employee-documents',
  false,
  10485760,
  array['application/pdf', 'image/jpeg', 'image/png']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "employee_documents_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'employee-documents' and public.is_hr_staff());

create policy "employee_documents_write" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'employee-documents' and public.is_hr_staff());

create policy "employee_documents_remove" on storage.objects
  for delete to authenticated
  using (bucket_id = 'employee-documents' and public.is_hr_staff());

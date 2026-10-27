-- Demo data for Smart HR Phase 1: the standard hotel departments, plus a roster
-- spanning every contract state so the alert dashboard has something to show.
-- Dates are relative to the run date.
-- Requires at least one row in public.hr_profiles (see scripts/create-hr-admin.sql).

insert into public.departments (name, description) values
  ('Front Office',             'Reception, reservations and guest relations.'),
  ('Housekeeping',             'Rooms, public areas and laundry.'),
  ('Food & Beverage Service',  'Restaurant, bar, banquet and in-room dining service.'),
  ('Food & Beverage Product',  'Kitchen, pastry and stewarding.'),
  ('Engineering',              'Building maintenance, utilities and safety systems.'),
  ('Sales & Marketing',        'Corporate sales, e-commerce and communications.'),
  ('Accounting',               'Finance, purchasing and cost control.'),
  ('Human Resources',          'Recruitment, people development and industrial relations.'),
  ('Security',                 'Property protection and guest safety.'),
  ('Spa & Recreation',         'Spa, pool, gym and guest activities.')
on conflict do nothing;

with admin as (select id from public.hr_profiles limit 1)
insert into public.employees (
  employee_id, full_name, phone, national_id, email, department_id, job_title,
  employment_status, join_date, end_date, is_active, notes, created_by
)
select
  seed.employee_id, seed.full_name, seed.phone, seed.national_id, seed.email,
  d.id, seed.job_title, seed.employment_status, seed.join_date, seed.end_date,
  seed.is_active, seed.notes, admin.id
from (values
  ('HTL-0101','Ayu Kartika Dewi','+62 811 2300 101','3171012509900001','ayu.dewi@smarthrhotel.com','Front Office','Front Desk Supervisor','PKWT', current_date - 400, current_date + 5,  true,  'Renewal discussion scheduled with Dept. Head.'),
  ('HTL-0102','Bagus Pratama','+62 812 4411 202','3171011204910002','bagus.pratama@smarthrhotel.com','Food & Beverage Service','Head Waiter','PKWT', current_date - 300, current_date + 18, true,  null),
  ('HTL-0103','Citra Maharani','+62 813 7788 303','3171010107930003','citra.maharani@smarthrhotel.com','Housekeeping','Room Attendant','PKWT', current_date - 180, current_date + 27, true,  'Strong performance review, recommend extension.'),
  ('HTL-0104','Dimas Nugroho','+62 815 2211 404','3171012903890004','dimas.nugroho@smarthrhotel.com','Engineering','Maintenance Technician','PKWT', current_date - 730, current_date - 6,  true,  'Contract lapsed - urgent, pending director signature.'),
  ('HTL-0105','Endah Puspita','+62 816 9900 505','3171011806950005','endah.puspita@smarthrhotel.com','Sales & Marketing','Sales Executive','PKWT', current_date - 120, current_date + 240,true,  null),
  ('HTL-0106','Fajar Ramadhan','+62 817 3344 606','3171010502870006','fajar.ramadhan@smarthrhotel.com','Front Office','Front Office Manager','PKWTT', current_date - 2200, null,            true,  null),
  ('HTL-0107','Gita Lestari','+62 818 5566 707','3171012411880007','gita.lestari@smarthrhotel.com','Human Resources','HR Officer','PKWTT', current_date - 1500, null,            true,  null),
  ('HTL-0108','Hendra Wijaya','+62 819 1122 808','3171010309820008','hendra.wijaya@smarthrhotel.com','Accounting','Chief Accountant','PKWTT', current_date - 3100, null,            true,  null),
  ('HTL-0109','Indah Permata','+62 821 6677 909','3171012007960009','indah.permata@smarthrhotel.com','Spa & Recreation','Spa Therapist','PKWT', current_date - 90,  current_date + 275,true,  null),
  ('HTL-0110','Joko Santoso','+62 822 8899 010','3171011512910010',null,'Security','Security Officer','Daily Worker', current_date - 45,  null,            true,  'Paid per shift; no fixed-term contract.'),
  ('HTL-0111','Kirana Ayu','+62 823 4455 111','3171010610940011','kirana.ayu@smarthrhotel.com','Food & Beverage Product','Pastry Cook','Daily Worker', current_date - 20,  null,            true,  null),
  ('HTL-0112','Lukman Hakim','+62 824 7788 212','3171012802850012','lukman.hakim@smarthrhotel.com','Housekeeping','Laundry Attendant','PKWT', current_date - 420, current_date + 60, true,  null),
  ('HTL-0098','Mira Anggraini','+62 825 1133 313','3171011709900013',null,'Front Office','Guest Relations Officer','PKWT', current_date - 1100, current_date - 120,false, null),
  ('HTL-0099','Nanda Saputra','+62 826 2244 414','3171010403880014',null,'Engineering','Electrician','PKWT', current_date - 950, current_date - 60,  false, null)
) as seed(employee_id, full_name, phone, national_id, email, department, job_title, employment_status, join_date, end_date, is_active, notes)
join public.departments d on lower(d.name) = lower(seed.department)
cross join admin
on conflict (employee_id) do nothing;

update public.employees set deactivation_reason = 'Resigned to join another property.' where employee_id = 'HTL-0098';
update public.employees set deactivation_reason = 'Contract concluded, not renewed.'  where employee_id = 'HTL-0099';


-- Phase 2 demo: portal access, one HOD, and two auto-scheduled backoffice staff.
update public.employees set portal_enabled = true
where employee_id in ('HTL-0101', 'HTL-0102', 'HTL-0103', 'HTL-0106') and email is not null;

update public.employees set role = 'hod' where employee_id = 'HTL-0106';

update public.employees
set auto_schedule_shift_id = (select id from public.master_shifts where code = 'BO')
where employee_id in ('HTL-0107', 'HTL-0108');


-- Phase 3 demo: a couple of national holidays so the overtime multiplier has
-- something to react to. Job levels and balances are created by the migrations
-- and on first use respectively.
insert into public.master_holidays (holiday_date, description) values
  (date_trunc('year', now())::date + interval '0 day',  'New Year''s Day'),
  (date_trunc('year', now())::date + interval '242 day','Independence Day')
on conflict (holiday_date) do nothing;

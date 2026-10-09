import { rpc } from '../lib/api';

export interface PoliceCase {
  id: number;
  event_id: number | null;
  location_id: string;
  statement: string;
  status: 'filed' | 'reviewing' | 'closed';
  created_at: string;
  event_title: string | null;
  event_body: string | null;
}
export const policeCases = () => rpc<PoliceCase[]>('police_cases_list');
export const policeReportRobbery = (eventId: number, statement: string) =>
  rpc<{ message: string; case_id: number }>('police_report_robbery', { p_event_id: eventId, p_statement: statement });
export const policeBail = () => rpc<{ message: string; paid: number; bank: number; cash: number }>('police_bail');

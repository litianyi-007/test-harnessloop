import { MembershipStatus, TenantKind } from '../../../database/entities';

/** openapi.yaml `components.schemas.Tenant`。 */
export class TenantDto {
  kind!: TenantKind;
  id?: string | null;
  name?: string | null;
}

/**
 * openapi.yaml `components.schemas.Seat`——命名沿用契约（对应本仓 MembershipEntity，
 * 见 membership.entity.ts 头注释里"Seat vs Membership 粒度差异"说明）。
 */
export class SeatDto {
  tenantId?: string;
  role!: string;
  status!: MembershipStatus;
}

/** openapi POST /tenant/current/invitations 201 响应。 */
export class CreateInvitationResponseDto {
  inviteLink!: string;
  inviteCode?: string;
  status?: string;
}

select plan_membership.subscriber_id, plan_membership.plan_id, children, spouses
from hibernate.plan_membership
left join
	(select plan_membership.subscriber_id, plan_membership.plan_id, count(*) as children
		from hibernate.plan_membership
		left join hibernate.plan
			on plan.id = plan_membership.plan_id
		left join hibernate.sponsorship
			on sponsorship.subscriber_id = plan_membership.subscriber_id and sponsorship.sponsor_id = plan.sponsor_id and sponsorship.person_id = plan_membership.person_id
		where
			plan_membership.person_id != plan_membership.subscriber_id
			and sponsorship.relationship_type = 'child'
			and (plan_membership.start_date < date('2016-11-01') and date('2016-10-01') < plan_membership.end_date) -- active during month
		group by plan_membership.subscriber_id, plan_membership.plan_id) as children_table
	on children_table.subscriber_id = plan_membership.subscriber_id and children_table.plan_id = plan_membership.plan_id
left join
	(select plan_membership.subscriber_id, plan_membership.plan_id, count(*) as spouses
	 	from hibernate.plan_membership
	 	left join hibernate.plan
	 		on plan.id = plan_membership.plan_id
	 	left join hibernate.sponsorship
	 		on sponsorship.subscriber_id = plan_membership.subscriber_id and sponsorship.sponsor_id = plan.sponsor_id and sponsorship.person_id = plan_membership.person_id
	 	where
	 		plan_membership.person_id != plan_membership.subscriber_id
	 		and sponsorship.relationship_type = 'spouse'
			and (plan_membership.start_date < date('2016-11-01') and date('2016-10-01') < plan_membership.end_date) -- active during month
	 	group by plan_membership.subscriber_id, plan_membership.plan_id) as spouse_table
	on spouse_table.subscriber_id = plan_membership.subscriber_id and spouse_table.plan_id = plan_membership.plan_id
where children > 0
group by plan_membership.subscriber_id, plan_membership.plan_id, children_table.children, spouse_table.spouses
order by plan_membership.subscriber_id ASC, plan_membership.plan_id ASC
limit 100;
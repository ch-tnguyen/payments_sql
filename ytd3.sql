-- need to calculate coverage tier for person for month
-- is the person coverege in the month, use wash rule
-- do they have a spouse covered in the month
-- do they have any children covered in the month?


DROP FUNCTION IF EXISTS wash_rule(INT, INT, DATE, DATE);
CREATE FUNCTION wash_rule(year INT, month INT, start_date DATE, end_date DATE)
RETURNS boolean AS $$
DECLARE
	mid_month timestamp;
BEGIN
	mid_month := make_timestamp(year, month, 16, 0, 0, 0); -- all of 15th is included in first half of month
	
	IF start_date < mid_month
	THEN
		IF end_date IS NULL
		THEN
			RETURN TRUE;
		ELSE
			RETURN mid_month <= end_date;
		END IF;
	ELSE
		RETURN FALSE;
	END IF;
END;
$$ LANGUAGE plpgsql;


DROP FUNCTION IF EXISTS count_dependents(TEXT, BIGINT, BIGINT, INT, INT);
CREATE FUNCTION count_dependents(relationship TEXT, sid BIGINT, pid BIGINT, year INT, month INT)
RETURNS INT AS $$
DECLARE
	end_month int;
	end_year int;
BEGIN

	IF (month = 12)
	THEN
		end_month = 1;
		end_year = year+1;
	ELSE
		end_month = month+1;
		end_year = year;
	END IF;

	return count(*)
	 	FROM hibernate.plan_membership
	 	LEFT JOIN hibernate.plan
	 		ON plan.id = plan_membership.plan_id
	 	LEFT JOIN hibernate.sponsorship
	 		ON sponsorship.subscriber_id = plan_membership.subscriber_id
			AND sponsorship.sponsor_id = plan.sponsor_id
			AND sponsorship.person_id = plan_membership.person_id
	 	WHERE
	 		plan_membership.subscriber_id = sid
	 		AND plan_membership.plan_id = pid
	 		AND plan_membership.person_id != plan_membership.subscriber_id
	 		AND sponsorship.relationship_type = relationship
			AND (
				-- active during month
				plan_membership.start_date < make_timestamp(end_year, end_month, 1, 0, 0, 0)
				AND
				make_timestamp(year, month, 1, 0, 0, 0) < plan_membership.end_date) 
	 	GROUP BY plan_membership.subscriber_id, plan_membership.plan_id;
END;
$$ LANGUAGE plpgsql;


-- returns [-/E][-/S][-/K/C]
DROP FUNCTION IF EXISTS calculate_coverage_tier(BIGINT, BIGINT, INT, INT);
CREATE FUNCTION calculate_coverage_tier(sid BIGINT, pid BIGINT, year INT, month INT)
RETURNS TEXT AS $$
DECLARE
	self TEXT;
	spouse TEXT;
	children TEXT;
	sdate DATE;
	edate DATE;
	c INT;
BEGIN
	-- determine if self is covered
	IF EXISTS (SELECT DISTINCT 1
			   FROM hibernate.plan_membership AS pm
			   WHERE pm.subscriber_id = sid AND pm.plan_id = pid)
	THEN
		SELECT pm.start_date, pm.end_date INTO sdate, edate
		FROM hibernate.plan_membership AS pm
		WHERE pm.subscriber_id = sid AND pm.plan_id = pid;
		
		IF wash_rule(year, month, sdate, edate)
		THEN
			SELECT 'E' INTO self;
		ELSE
			SELECT '-' INTO self;
		END IF;
	ELSE
		SELECT '-' INTO self;
	END IF;
	
	-- determine if spouse is covered
	SELECT count_dependents('spouse', sid, pid, year, month) INTO c;
	IF (c IS NOT NULL AND c > 0)
	THEN
		SELECT 'S' INTO spouse;
	ELSE
		SELECT '-' INTO spouse;
	END IF;
	
	-- determine how many children are covered
	SELECT count_dependents('spouse', sid, pid, year, month) INTO c;
	IF (c IS NOT NULL AND c = 1)
	THEN
		SELECT 'K' INTO children;
	ELSIF (c != NULL AND c > 1)
	THEN
		SELECT 'C' INTO children;
	ELSE
		SELECT '-' INTO children;
	END IF;
	
	return self || spouse || children;
END;
$$ LANGUAGE plpgsql;

select
	pm.person_id,
	pm.subscriber_id,
	pm.plan_id,
	sponsorship.sponsor_id,
	pm.start_date,
	pm.end_date,
	plan.name as "Plan Name",
	partner.name as "Partner",
	sponsor.name as "Sponsor",
	'tbd' as "Subsidiary",
	sponsorship.sponsorship_type as "Relationship",
	pm.is_cobra as "COBRA",
	date_part('year', CURRENT_DATE) as year,
	year_months_to_date.month,
	wash_rule(cast(date_part('year', CURRENT_DATE) as INT), year_months_to_date.month, pm.start_date, pm.end_date) as count,
	calculate_coverage_tier(pm.subscriber_id, plan.id, cast(date_part('year', CURRENT_DATE) as INT), year_months_to_date.month) as "Tier"
from hibernate.plan_membership as pm
cross join (select generate_series(1, cast(date_part('month', CURRENT_DATE) as INT)) as month) as year_months_to_date
left join hibernate.plan
	on pm.plan_id = plan.id
left join hibernate.partner
	on plan.network_partner_id = partner.id
left join hibernate.sponsorship
	on pm.person_id = sponsorship.person_id
	and pm.subscriber_id = sponsorship.person_id
left join hibernate.sponsor
	on sponsorship.sponsor_id = sponsor.id
where plan.type = 'MEDICAL' and sponsor.id is not null
group by pm.person_id, pm.subscriber_id, pm.plan_id, sponsorship.sponsor_id, plan.id, plan.name, partner.name, sponsor.name, sponsorship.sponsorship_type, pm.is_cobra, year_months_to_date.month, pm.start_date, pm.end_date
order by pm.person_id, pm.subscriber_id, pm.plan_id, sponsorship.sponsor_id, year, month;
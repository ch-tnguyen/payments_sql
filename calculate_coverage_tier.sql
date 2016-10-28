-- need to calculate coverage tier for person for month
-- is the person coverege in the month, use wash rule
-- do they have a spouse covered in the month
-- do they have any children covered in the month?


DROP FUNCTION IF EXISTS wash_rule(INTEGER, INTEGER, DATE, DATE);
CREATE FUNCTION wash_rule(year INTEGER, month INTEGER, start_date DATE, end_date DATE)
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


DROP FUNCTION IF EXISTS count_dependents(TEXT, INT, INT, INT, INT);
CREATE FUNCTION count_dependents(relationship TEXT, sid INT, pid INT, year INT, month INT)
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
DROP FUNCTION IF EXISTS calculate_coverage_tier(INT, INT, INT, INT);
CREATE FUNCTION calculate_coverage_tier(sid INT, pid INT, year INT, month INT)
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
	
	-- determin if children are covered
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

SELECT calculate_coverage_tier(3423, 1108, 2015, 12);
SELECT calculate_coverage_tier(3423, 1108, 2016, 01);
SELECT calculate_coverage_tier(3423, 1108, 2016, 02);
SELECT calculate_coverage_tier(3423, 1108, 2016, 03);
SELECT calculate_coverage_tier(3423, 1108, 2016, 04);
SELECT calculate_coverage_tier(3423, 1108, 2016, 05);
SELECT calculate_coverage_tier(3423, 1108, 2016, 06);
SELECT calculate_coverage_tier(3423, 1108, 2016, 07);
SELECT calculate_coverage_tier(3423, 1108, 2016, 08);
SELECT calculate_coverage_tier(3423, 1108, 2016, 09);
SELECT calculate_coverage_tier(3423, 1108, 2016, 10);
SELECT calculate_coverage_tier(3423, 1108, 2016, 11);
SELECT calculate_coverage_tier(3423, 1108, 2016, 12);
SELECT calculate_coverage_tier(3423, 1108, 2017, 01);